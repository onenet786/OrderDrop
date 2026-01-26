ALTER TABLE users ADD reset_password_token VARCHAR(255) DEFAULT NULL;
ALTER TABLE users ADD reset_password_expires TIMESTAMP DEFAULT NULL;

ALTER TABLE riders ADD reset_password_token VARCHAR(255) DEFAULT NULL;
ALTER TABLE riders ADD reset_password_expires TIMESTAMP DEFAULT NULL;
