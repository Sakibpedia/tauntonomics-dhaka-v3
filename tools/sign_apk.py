#!/usr/bin/env python3
"""sign_apk.py — signs an Android APK with APK Signature Scheme v2 (and zip-aligns stored entries),
implemented from the published specification (source.android.com/docs/security/features/apksigning/v2)
using only Python's `cryptography` package. Use it when the Android SDK's apksigner isn't installed.

    python sign_apk.py unsigned.apk signed.apk [--key key.pem --cert cert.der]

Without --key/--cert it creates (once) a 2048-bit RSA key and a 30-year self-signed certificate in
tools/android_signing/. Keep those files: Android only accepts updates signed with the same key.
For Google Play, sign with your own upload key instead (Godot's exporter + apksigner, or Play App Signing).
v2 is valid on Android 7.0+ (Godot 4.6's minimum is Android 7, API 24).
"""
import argparse
import datetime
import hashlib
import os
import struct
import sys
import zlib

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.x509.oid import NameOID

APK_SIG_BLOCK_MAGIC = b"APK Sig Block 42"
V2_ID = 0x7109871A
ALGO_RSA_PKCS1_SHA256 = 0x0103
CHUNK = 1024 * 1024


def lp(b: bytes) -> bytes:
    return struct.pack("<I", len(b)) + b


def find_eocd(data: bytes) -> int:
    for i in range(len(data) - 22, max(-1, len(data) - 22 - 65536), -1):
        if data[i:i + 4] == b"PK\x05\x06":
            return i
    raise SystemExit("not a zip: no end of central directory")


def zipalign(data: bytes, align: int = 4) -> bytes:
    """Rewrites local headers so STORED entries start on `align`-byte boundaries (so are .so files at 4096)."""
    eocd = find_eocd(data)
    cd_size, cd_off = struct.unpack("<II", data[eocd + 12:eocd + 20])
    count = struct.unpack("<H", data[eocd + 10:eocd + 12])[0]
    out = bytearray()
    new_cd = bytearray()
    p = cd_off
    for _ in range(count):
        (sig, vmade, vneed, flag, method, mtime, mdate, crc, csize, usize, nlen, xlen, clen, disk, iattr, eattr,
         loff) = struct.unpack("<IHHHHHHIIIHHHHHII", data[p:p + 46])
        name = data[p + 46:p + 46 + nlen]
        cextra = data[p + 46 + nlen:p + 46 + nlen + xlen]
        ccomment = data[p + 46 + nlen + xlen:p + 46 + nlen + xlen + clen]
        p += 46 + nlen + xlen + clen
        lh = data[loff:loff + 30]
        lnlen, lxlen = struct.unpack("<HH", lh[26:30])
        lname = data[loff + 30:loff + 30 + lnlen]
        start = loff + 30 + lnlen + lxlen
        body = data[start:start + csize]
        new_off = len(out)
        extra = b""
        if method == 0:
            a = 4096 if name.endswith(b".so") else align
            pad = (a - (new_off + 30 + lnlen) % a) % a
            extra = b"\x00" * pad
        hdr = bytearray(lh)
        hdr[28:30] = struct.pack("<H", len(extra))
        out += hdr + lname + extra + body
        if flag & 0x08:     # data descriptor
            dd = data[start + csize:start + csize + 16]
            if dd[:4] == b"PK\x07\x08":
                out += dd
            else:
                out += dd[:12]
        new_cd += struct.pack("<IHHHHHHIIIHHHHHII", sig, vmade, vneed, flag, method, mtime, mdate, crc, csize, usize,
                              nlen, xlen, clen, disk, iattr, eattr, new_off) + name + cextra + ccomment
    eocd_rec = bytearray(data[eocd:])
    eocd_rec[12:16] = struct.pack("<I", len(new_cd))
    eocd_rec[16:20] = struct.pack("<I", len(out))
    return bytes(out + new_cd + eocd_rec)


def strip_existing_block(data: bytes):
    eocd = find_eocd(data)
    cd_size, cd_off = struct.unpack("<II", data[eocd + 12:eocd + 20])
    start = cd_off
    if data[cd_off - 16:cd_off] == APK_SIG_BLOCK_MAGIC:
        size = struct.unpack("<Q", data[cd_off - 24:cd_off - 16])[0]
        start = cd_off - size - 8
    return data[:start], data[cd_off:cd_off + cd_size], data[eocd:]


def chunk_digest(sections) -> bytes:
    digests = []
    for sec in sections:
        for i in range(0, len(sec), CHUNK):
            c = sec[i:i + CHUNK]
            digests.append(hashlib.sha256(b"\xa5" + struct.pack("<I", len(c)) + c).digest())
    return hashlib.sha256(b"\x5a" + struct.pack("<I", len(digests)) + b"".join(digests)).digest()


def load_or_create_key(key_path: str, cert_path: str):
    if os.path.exists(key_path) and os.path.exists(cert_path):
        key = serialization.load_pem_private_key(open(key_path, "rb").read(), None)
        cert = x509.load_der_x509_certificate(open(cert_path, "rb").read())
        return key, cert
    os.makedirs(os.path.dirname(key_path), exist_ok=True)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "S M Nazmuz Sakib"),
                      x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Taunt-o-Nomics"),
                      x509.NameAttribute(NameOID.COUNTRY_NAME, "BD")])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(x509.random_serial_number()).not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=365 * 30)).sign(key, hashes.SHA256()))
    open(key_path, "wb").write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                                 serialization.NoEncryption()))
    open(cert_path, "wb").write(cert.public_bytes(serialization.Encoding.DER))
    return key, cert


def sign(inp: str, outp: str, key_path: str, cert_path: str) -> None:
    data = zipalign(open(inp, "rb").read())
    sec1, cd, eocd = strip_existing_block(data)
    key, cert = load_or_create_key(key_path, cert_path)
    eocd_for_digest = bytearray(eocd)
    eocd_for_digest[16:20] = struct.pack("<I", len(sec1))
    digest = chunk_digest([sec1, cd, bytes(eocd_for_digest)])
    cert_der = cert.public_bytes(serialization.Encoding.DER)
    pub_der = key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    digests = lp(lp(struct.pack("<I", ALGO_RSA_PKCS1_SHA256) + lp(digest)))
    certs = lp(lp(cert_der))
    signed_data = digests + certs + lp(b"")
    sig = key.sign(signed_data, padding.PKCS1v15(), hashes.SHA256())
    signer = lp(signed_data) + lp(lp(struct.pack("<I", ALGO_RSA_PKCS1_SHA256) + lp(sig))) + lp(pub_der)
    v2_value = lp(lp(signer))
    pairs = struct.pack("<Q", 4 + len(v2_value)) + struct.pack("<I", V2_ID) + v2_value
    size = len(pairs) + 8 + 16
    block = struct.pack("<Q", size) + pairs + struct.pack("<Q", size) + APK_SIG_BLOCK_MAGIC
    new_eocd = bytearray(eocd)
    new_eocd[16:20] = struct.pack("<I", len(sec1) + len(block))
    open(outp, "wb").write(sec1 + block + cd + bytes(new_eocd))
    print("signed (APK Signature Scheme v2):", outp, "%.1f MB" % (os.path.getsize(outp) / 1e6))
    print("certificate SHA-256:", hashlib.sha256(cert_der).hexdigest())


def verify(path: str) -> bool:
    """Re-computes the v2 digest and checks the signature (self-test)."""
    data = open(path, "rb").read()
    eocd = find_eocd(data)
    cd_size, cd_off = struct.unpack("<II", data[eocd + 12:eocd + 20])
    assert data[cd_off - 16:cd_off] == APK_SIG_BLOCK_MAGIC, "no signing block"
    size = struct.unpack("<Q", data[cd_off - 24:cd_off - 16])[0]
    bstart = cd_off - size - 8
    sec1 = data[:bstart]
    e = bytearray(data[eocd:])
    e[16:20] = struct.pack("<I", bstart)
    want = chunk_digest([sec1, data[cd_off:cd_off + cd_size], bytes(e)])
    blk = data[bstart + 8:cd_off - 24]
    plen, pid = struct.unpack("<QI", blk[:12])
    val = blk[12:8 + plen]
    signer = val[8:]
    sd_len = struct.unpack("<I", signer[:4])[0]
    sd = signer[4:4 + sd_len]
    rest = signer[4 + sd_len:]
    sigs_len = struct.unpack("<I", rest[:4])[0]
    sigs = rest[4:4 + sigs_len]
    pk = rest[4 + sigs_len + 4:]
    sig = sigs[4 + 4 + 4:]
    pub = serialization.load_der_public_key(pk)
    pub.verify(sig, sd, padding.PKCS1v15(), hashes.SHA256())
    got = sd[4 + 4 + 4 + 4:4 + 4 + 4 + 4 + 32]
    ok = got == want and pid == V2_ID
    # alignment check of stored entries
    p = cd_off
    count = struct.unpack("<H", data[eocd + 10:eocd + 12])[0]
    bad = 0
    for _ in range(count):
        f = struct.unpack("<IHHHHHHIIIHHHHHII", data[p:p + 46])
        nlen, xlen, clen, loff = f[10], f[11], f[12], f[16]
        name = data[p + 46:p + 46 + nlen]
        if f[4] == 0:
            lnlen, lxlen = struct.unpack("<HH", data[loff + 26:loff + 30])
            if (loff + 30 + lnlen + lxlen) % 4:
                bad += 1
        p += 46 + nlen + xlen + clen
    print("verify:", "OK" if ok else "DIGEST MISMATCH", "| misaligned stored entries:", bad)
    return ok and bad == 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("inp")
    ap.add_argument("out")
    here = os.path.dirname(os.path.abspath(__file__))
    ap.add_argument("--key", default=os.path.join(here, "android_signing", "taunt_key.pem"))
    ap.add_argument("--cert", default=os.path.join(here, "android_signing", "taunt_cert.der"))
    a = ap.parse_args()
    sign(a.inp, a.out, a.key, a.cert)
    sys.exit(0 if verify(a.out) else 1)
