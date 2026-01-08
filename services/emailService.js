const nodemailer = require('nodemailer');

// Create transporter only if credentials exist
let transporter = null;

if (process.env.EMAIL_USER && process.env.EMAIL_PASS) {
    transporter = nodemailer.createTransport({
        service: 'gmail', // Or use generic SMTP
        auth: {
            user: process.env.EMAIL_USER,
            pass: process.env.EMAIL_PASS
        }
    });
}

/**
 * Send verification code to email
 * @param {string} email 
 * @param {string} code 
 */
async function sendVerificationEmail(email, code) {
    const subject = 'Your Verification Code - ServeNow';
    const text = `Your verification code is: ${code}. It will expire in 10 minutes.`;
    const html = `
        <div style="font-family: Arial, sans-serif; padding: 20px;">
            <h2>Welcome to ServeNow!</h2>
            <p>Please use the following code to verify your email address:</p>
            <h1 style="color: #4CAF50; letter-spacing: 5px;">${code}</h1>
            <p>This code will expire in 10 minutes.</p>
            <p>If you didn't request this, please ignore this email.</p>
        </div>
    `;

    if (transporter) {
        try {
            await transporter.sendMail({
                from: `"ServeNow" <${process.env.EMAIL_USER}>`,
                to: email,
                subject: subject,
                text: text,
                html: html
            });
            console.log(`Verification email sent to ${email}`);
            return true;
        } catch (error) {
            console.error('Error sending email:', error);
            // Fallback to console log in dev
            console.log('----------------------------------------');
            console.log(`To: ${email}`);
            console.log(`Code: ${code}`);
            console.log('----------------------------------------');
            return false;
        }
    } else {
        console.warn('Email credentials not found. Logging code to console.');
        console.log('----------------------------------------');
        console.log(`[MOCK EMAIL] To: ${email}`);
        console.log(`[MOCK EMAIL] Code: ${code}`);
        console.log('----------------------------------------');
        return true; // Pretend it worked
    }
}

/**
 * Send account deletion request email to support
 * @param {string} userEmail 
 * @param {string} reason 
 */
async function sendDeletionRequestEmail(userEmail, reason) {
    const supportEmail = 'onenetpk@gmail.com'; // User specified email
    const subject = 'Account Deletion Request - ServeNow';
    const text = `A new account deletion request has been received.\n\nUser Email: ${userEmail}\nReason: ${reason || 'Not provided'}`;
    const html = `
        <div style="font-family: Arial, sans-serif; padding: 20px;">
            <h2>Account Deletion Request</h2>
            <p>A new account deletion request has been received from the web form.</p>
            <p><strong>User Email:</strong> ${userEmail}</p>
            <p><strong>Reason:</strong> ${reason || 'Not provided'}</p>
            <p>Please process this request within 48-72 hours.</p>
        </div>
    `;

    if (transporter) {
        try {
            await transporter.sendMail({
                from: `"ServeNow System" <${process.env.EMAIL_USER}>`,
                to: supportEmail,
                subject: subject,
                text: text,
                html: html
            });
            console.log(`Deletion request email sent to support for ${userEmail}`);
            return true;
        } catch (error) {
            console.error('Error sending deletion request email:', error);
            return false;
        }
    } else {
        console.warn('Email credentials not found. Logging deletion request to console.');
        console.log('----------------------------------------');
        console.log(`[MOCK EMAIL] To: ${supportEmail}`);
        console.log(`[MOCK EMAIL] Request from: ${userEmail}`);
        console.log(`[MOCK EMAIL] Reason: ${reason}`);
        console.log('----------------------------------------');
        return true;
    }
}

module.exports = {
    sendVerificationEmail,
    sendDeletionRequestEmail
};
