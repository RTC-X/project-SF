
import hashlib
secret = "myPassword$gxdaf123"
user_id = 1
expected_key = f"c2_usr_{hashlib.sha256(f\"{user_id}:{secret}\".encode()).hexdigest()[:16]}"
print("Expected:", expected_key)

