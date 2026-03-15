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

async function ensurePermissionGroupTables(db) {
    try {
        await db.query(`
            CREATE TABLE IF NOT EXISTS permission_groups (
                id INT PRIMARY KEY AUTO_INCREMENT,
                name VARCHAR(100) NOT NULL UNIQUE,
                description VARCHAR(255) NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        `);
        await db.query(`
            CREATE TABLE IF NOT EXISTS permission_group_permissions (
                id INT PRIMARY KEY AUTO_INCREMENT,
                group_id INT NOT NULL,
                permission_key VARCHAR(100) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY unique_group_perm (group_id, permission_key),
                FOREIGN KEY (group_id) REFERENCES permission_groups(id) ON DELETE CASCADE
            )
        `);
        await db.query(`
            CREATE TABLE IF NOT EXISTS user_permission_groups (
                id INT PRIMARY KEY AUTO_INCREMENT,
                user_id INT NOT NULL,
                group_id INT NOT NULL,
                assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY unique_user_group (user_id),
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (group_id) REFERENCES permission_groups(id) ON DELETE CASCADE
            )
        `);
    } catch (err) {
        console.error("Error creating permission group tables:", err);
    }
}

async function getGroupPermissions(db, groupId) {
    const [rows] = await db.execute(
        "SELECT permission_key FROM permission_group_permissions WHERE group_id = ?",
        [groupId]
    );
    return rows.map((r) => r.permission_key);
}

async function syncGroupMembersPermissions(db, groupId, permissions) {
    const perms = Array.isArray(permissions) ? permissions : await getGroupPermissions(db, groupId);
    const [members] = await db.execute(
        "SELECT user_id FROM user_permission_groups WHERE group_id = ?",
        [groupId]
    );
    const userIds = members
        .map((m) => Number.parseInt(m.user_id, 10))
        .filter((id) => Number.isInteger(id) && id > 0);
    if (!userIds.length) return;

    const connection = await db.getConnection();
    try {
        await connection.beginTransaction();
        const deletePlaceholders = userIds.map(() => "?").join(",");
        await connection.execute(
            `DELETE FROM user_permissions WHERE user_id IN (${deletePlaceholders})`,
            userIds
        );

        if (perms.length > 0) {
            const placeholders = [];
            const values = [];
            userIds.forEach((userId) => {
                perms.forEach((perm) => {
                    placeholders.push("(?, ?)");
                    values.push(userId, perm);
                });
            });
            await connection.execute(
                `INSERT INTO user_permissions (user_id, permission_key) VALUES ${placeholders.join(",")}`,
                values
            );
        }

        await connection.commit();
    } catch (err) {
        await connection.rollback();
        throw err;
    } finally {
        connection.release();
    }
}

// Get all users for assignment (Admin only)
router.get('/users', authenticateToken, requireAdmin, async (req, res) => {
    try {
        await ensurePermissionGroupTables(req.db);
        const [users] = await req.db.execute(`
            SELECT id, first_name, last_name, email, user_type, phone 
            FROM users 
            WHERE user_type = 'standard_user'
            ORDER BY first_name ASC
        `);
        const userIds = users.map((u) => u.id);
        let groupMap = new Map();
        if (userIds.length) {
            const placeholders = userIds.map(() => "?").join(",");
            const [groupRows] = await req.db.execute(
                `
                SELECT ug.user_id, g.id AS group_id, g.name AS group_name
                FROM user_permission_groups ug
                JOIN permission_groups g ON g.id = ug.group_id
                WHERE ug.user_id IN (${placeholders})
                `,
                userIds
            );
            groupMap = new Map(groupRows.map((r) => [r.user_id, { group_id: r.group_id, group_name: r.group_name }]));
        }
        const payload = users.map((u) => ({
            ...u,
            group_id: groupMap.get(u.id)?.group_id || null,
            group_name: groupMap.get(u.id)?.group_name || null
        }));
        res.json({ success: true, users: payload });
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

router.get('/user/:id/group', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const { id } = req.params;
        await ensurePermissionGroupTables(req.db);
        const [rows] = await req.db.execute(
            `
            SELECT g.id, g.name, g.description
            FROM user_permission_groups ug
            JOIN permission_groups g ON g.id = ug.group_id
            WHERE ug.user_id = ?
            `,
            [id]
        );
        const group = rows[0] || null;
        res.json({ success: true, group });
    } catch (error) {
        console.error('Error fetching user group:', error);
        res.status(500).json({ success: false, message: 'Failed to fetch user group' });
    }
});

router.post('/user/:id/group', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const { id } = req.params;
        const groupId = req.body?.group_id ? Number(req.body.group_id) : null;
        await ensurePermissionsTable(req.db);
        await ensurePermissionGroupTables(req.db);

        if (groupId && !Number.isInteger(groupId)) {
            return res.status(400).json({ success: false, message: 'Invalid group_id' });
        }

        let groupPermissions = [];
        if (groupId) {
            const [groupRows] = await req.db.execute(
                "SELECT id FROM permission_groups WHERE id = ?",
                [groupId]
            );
            if (!groupRows.length) {
                return res.status(404).json({ success: false, message: 'Group not found' });
            }
            groupPermissions = await getGroupPermissions(req.db, groupId);
        }

        const connection = await req.db.getConnection();
        try {
            await connection.beginTransaction();
            await connection.execute('DELETE FROM user_permission_groups WHERE user_id = ?', [id]);
            if (groupId) {
                await connection.execute(
                    'INSERT INTO user_permission_groups (user_id, group_id) VALUES (?, ?)',
                    [id, groupId]
                );
            }

            await connection.execute('DELETE FROM user_permissions WHERE user_id = ?', [id]);
            if (groupPermissions.length > 0) {
                const placeholders = groupPermissions.map(() => '(?, ?)').join(',');
                const values = [];
                groupPermissions.forEach((perm) => {
                    values.push(id, perm);
                });
                await connection.execute(
                    `INSERT INTO user_permissions (user_id, permission_key) VALUES ${placeholders}`,
                    values
                );
            }

            await connection.commit();
        } catch (err) {
            await connection.rollback();
            throw err;
        } finally {
            connection.release();
        }

        res.json({ success: true, message: 'User group updated successfully' });
    } catch (error) {
        console.error('Error updating user group:', error);
        res.status(500).json({ success: false, message: 'Failed to update user group' });
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

router.get('/groups', authenticateToken, requireAdmin, async (req, res) => {
    try {
        await ensurePermissionGroupTables(req.db);
        const [groups] = await req.db.execute(
            `
            SELECT
                g.id,
                g.name,
                g.description,
                (SELECT COUNT(*) FROM permission_group_permissions gp WHERE gp.group_id = g.id) AS permissions_count,
                (SELECT COUNT(*) FROM user_permission_groups ug WHERE ug.group_id = g.id) AS member_count
            FROM permission_groups g
            ORDER BY g.name ASC
            `
        );
        res.json({ success: true, groups });
    } catch (error) {
        console.error('Error loading permission groups:', error);
        res.status(500).json({ success: false, message: 'Failed to load groups' });
    }
});

router.post('/groups', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const name = String(req.body?.name || '').trim();
        const description = String(req.body?.description || '').trim();
        if (!name) {
            return res.status(400).json({ success: false, message: 'Group name is required' });
        }
        await ensurePermissionGroupTables(req.db);
        const [result] = await req.db.execute(
            "INSERT INTO permission_groups (name, description) VALUES (?, ?)",
            [name, description || null]
        );
        res.json({ success: true, group_id: result.insertId });
    } catch (error) {
        if (error && error.code === 'ER_DUP_ENTRY') {
            return res.status(409).json({ success: false, message: 'Group name already exists' });
        }
        console.error('Error creating permission group:', error);
        res.status(500).json({ success: false, message: 'Failed to create group' });
    }
});

router.put('/groups/:id', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const { id } = req.params;
        const name = String(req.body?.name || '').trim();
        const description = String(req.body?.description || '').trim();
        if (!name) {
            return res.status(400).json({ success: false, message: 'Group name is required' });
        }
        await ensurePermissionGroupTables(req.db);
        const [result] = await req.db.execute(
            "UPDATE permission_groups SET name = ?, description = ? WHERE id = ?",
            [name, description || null, id]
        );
        if (!result.affectedRows) {
            return res.status(404).json({ success: false, message: 'Group not found' });
        }
        res.json({ success: true, message: 'Group updated successfully' });
    } catch (error) {
        if (error && error.code === 'ER_DUP_ENTRY') {
            return res.status(409).json({ success: false, message: 'Group name already exists' });
        }
        console.error('Error updating permission group:', error);
        res.status(500).json({ success: false, message: 'Failed to update group' });
    }
});

router.delete('/groups/:id', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const { id } = req.params;
        await ensurePermissionsTable(req.db);
        await ensurePermissionGroupTables(req.db);
        const [members] = await req.db.execute(
            "SELECT user_id FROM user_permission_groups WHERE group_id = ?",
            [id]
        );
        const userIds = members
            .map((m) => Number.parseInt(m.user_id, 10))
            .filter((v) => Number.isInteger(v) && v > 0);

        const [result] = await req.db.execute("DELETE FROM permission_groups WHERE id = ?", [id]);
        if (!result.affectedRows) {
            return res.status(404).json({ success: false, message: 'Group not found' });
        }

        if (userIds.length) {
            const placeholders = userIds.map(() => "?").join(",");
            await req.db.execute(
                `DELETE FROM user_permissions WHERE user_id IN (${placeholders})`,
                userIds
            );
        }

        res.json({ success: true, message: 'Group deleted successfully' });
    } catch (error) {
        console.error('Error deleting permission group:', error);
        res.status(500).json({ success: false, message: 'Failed to delete group' });
    }
});

router.get('/group/:id/permissions', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const { id } = req.params;
        await ensurePermissionGroupTables(req.db);
        const permissions = await getGroupPermissions(req.db, id);
        res.json({ success: true, permissions });
    } catch (error) {
        console.error('Error fetching group permissions:', error);
        res.status(500).json({ success: false, message: 'Failed to fetch group permissions' });
    }
});

router.post('/group/:id/permissions', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const { id } = req.params;
        const { permissions } = req.body;
        if (!Array.isArray(permissions)) {
            return res.status(400).json({ success: false, message: 'Permissions must be an array' });
        }
        await ensurePermissionsTable(req.db);
        await ensurePermissionGroupTables(req.db);

        const connection = await req.db.getConnection();
        try {
            await connection.beginTransaction();
            await connection.execute(
                "DELETE FROM permission_group_permissions WHERE group_id = ?",
                [id]
            );

            if (permissions.length > 0) {
                const placeholders = permissions.map(() => "(?, ?)").join(",");
                const values = [];
                permissions.forEach((p) => values.push(id, p));
                await connection.execute(
                    `INSERT INTO permission_group_permissions (group_id, permission_key) VALUES ${placeholders}`,
                    values
                );
            }

            await connection.commit();
        } catch (err) {
            await connection.rollback();
            throw err;
        } finally {
            connection.release();
        }

        await syncGroupMembersPermissions(req.db, id, permissions);
        res.json({ success: true, message: 'Group permissions updated successfully' });
    } catch (error) {
        console.error('Error updating group permissions:', error);
        res.status(500).json({ success: false, message: 'Failed to update group permissions' });
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
