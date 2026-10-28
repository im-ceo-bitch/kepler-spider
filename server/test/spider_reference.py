# Independent reference check for wallet Spider derivation against Rust protocol address algorithm.
import hashlib, hmac, json
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
phrase = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about'
seed = hashlib.pbkdf2_hmac('sha512',phrase.encode(),b'mnemonic',2048,64)
I=hmac.new(b'ed25519 seed',seed,'sha512').digest()
for i in [44,9999,0,0]:
 I=hmac.new(I[32:],bytes([0])+I[:32]+((i|0x80000000).to_bytes(4,'big')),'sha512').digest()
priv = Ed25519PrivateKey.from_private_bytes(I[:32]);pub=priv.public_key().public_bytes(encoding=serialization.Encoding.Raw,format=serialization.PublicFormat.Raw)
payload=hashlib.sha256(pub).digest()[:20]
charset='qpzry9x8gf2tvdw0s3jn54khce6mua7l'
def convertbits(data,frombits,tobits,pad=True):
 acc=bits=0;ret=[];maxv=(1<<tobits)-1
 for value in data:
  acc=((acc<<frombits)|value)&0xffff;bits+=frombits
  while bits>=tobits:
   bits-=tobits;ret.append((acc>>bits)&maxv)
 if pad and bits:ret.append((acc<<(tobits-bits))&maxv)
 return ret
def polymod(values):
 c=1;gen=[0x3b6a57b2,0x26508e6d,0x1ea119fa,0x3d4233dd,0x2a1462b3]
 for v in values:
  b=c>>25;c=((c&0x1ffffff)<<5)^v
  for i in range(5):
   if b>>i&1:c^=gen[i]
 return c
hrp='spider'; five=convertbits(payload,8,5)
values=[ord(x)>>5 for x in hrp]+[0]+[ord(x)&31 for x in hrp]+five+[0]*6
checksum=polymod(values)^0x2bc830a3
ch=[(checksum>>(5*(5-i)))&31 for i in range(6)]
address=hrp+'1'+''.join(charset[d] for d in five+ch)
print(json.dumps({'mnemonic':'BIP39 public test mnemonic (never use for real funds)','derivation':"m/44'/9999'/0'/0'",'public_key_hex':pub.hex(),'address':address},indent=2))
