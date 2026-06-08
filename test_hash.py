
import hashlib

def print_hash(secret, uid):
    h = hashlib.sha256(f"{uid}:{secret}".encode()).hexdigest()
    print(f"c2_usr_{h[:16]}")

print_hash("myPassword$gxdaf", 1)
print_hash("myPassword$$gxdaf", 1)
print_hash("myPasswordgxdaf", 1)

