const express = require('express');
const { authenticateToken, requireAdmin } = require('../middleware/auth');
const router = express.Router();

// Ensure permissions table exists
async function ensurePermissionsTable(db) {
    try {
        await db.query(`
            CREATE TABLE IF NOT EXISTS user_permissions (
                id INT PRIMARY KEY AUTO_INCREMENT,
                user_id INT NOT NULL,
                permission_key VARCHAR(100) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY unique_user_perm (user_id, permission_key),
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        `);
        // console.log("Verified user_permissions table exists");
    } catch (err) {
        console.error("Error creating user_permissions table:", err);
    }
}

// Get all users for assignment (Admin only)
router.get('/users', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const [users] = await req.db.execute(`
            SELECT id, first_name, last_name, email, user_type, phone 
            FROM users 
            WHERE user_type = 'standard_user' 
            ORDER BY first_name ASC
        `);
        res.json({ success: true, users });
    } catch (error) {
        console.error('Error fetching users:', error);
        res.status(500).json({ success: false, message: 'Failed to fetch users' });
    }
});

// Get permissions for a specific user
router.get('/user/:id', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const { id } = req.params;
        await ensurePermissionsTable(req.db);
        
        const [rows] = await req.db.execute(
            'SELECT permission_key FROM user_permissions WHERE user_id = ?',
            [id]
        );
        
        const permissions = rows.map(r => r.permission_key);
        res.json({ success: true, permissions });
    } catch (error) {
        console.error('Error fetching user permissions:', error);
        res.status(500).json({ success: false, message: 'Failed to fetch permissions' });
    }
});

// Update permissions for a specific user
router.post('/user/:id', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const { id } = req.params;
        const { permissions } = req.body; // Array of permission keys
        
        if (!Array.isArray(permissions)) {
            return res.status(400).json({ success: false, message: 'Permissions must be an array' });
        }

        await ensurePermissionsTable(req.db);
        
        const connection = await req.db.getConnection();
        try {
            await connection.beginTransaction();
            
            // Remove existing permissions
            await connection.execute('DELETE FROM user_permissions WHERE user_id = ?', [id]);
            
            // Add new permissions
            if (permissions.length > 0) {
                const placeholders = permissions.map(() => '(?, ?)').join(',');
                const values = [];
                permissions.forEach(p => {
                    values.push(id, p);
                });
                
                await connection.execute(
                    `INSERT INTO user_permissions (user_id, permission_key) VALUES ${placeholders}`,
                    values
                );
            }
            
            await connection.commit();
            res.json({ success: true, message: 'Permissions updated successfully' });
        } catch (err) {
            await connection.rollback();
            throw err;
        } finally {
            connection.release();
        }
    } catch (error) {
        console.error('Error updating permissions:', error);
        res.status(500).json({ success: false, message: 'Failed to update permissions' });
    }
});

// Get my permissions (for logged in user)
router.get('/my-permissions', authenticateToken, async (req, res) => {
    try {
        // Admins have all permissions implicitly, but we return a special flag or list
        if (req.user.user_type === 'admin') {
            return res.json({ success: true, isAdmin: true, permissions: ['*'] });
        }

        await ensurePermissionsTable(req.db);
        
        const [rows] = await req.db.execute(
            'SELECT permission_key FROM user_permissions WHERE user_id = ?',
            [req.user.id]
        );
        
        const permissions = rows.map(r => r.permission_key);
        res.json({ success: true, permissions });
    } catch (error) {
        console.error('Error fetching my permissions:', error);
        res.status(500).json({ success: false, message: 'Failed to fetch permissions' });
    }
});

module.exports = router;
