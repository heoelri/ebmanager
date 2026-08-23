UPDATE sessions SET token = SHA2(token, 256);
