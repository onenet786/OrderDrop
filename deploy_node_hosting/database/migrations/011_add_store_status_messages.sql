CREATE TABLE IF NOT EXISTS store_status_messages (
    id INT PRIMARY KEY AUTO_INCREMENT,
    store_id INT NOT NULL,
    status_message TEXT NULL,
    is_closed BOOLEAN DEFAULT FALSE,
    updated_by INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_store_status_message_store (store_id),
    CONSTRAINT fk_store_status_message_store
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
    CONSTRAINT fk_store_status_message_updated_by
        FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
);
