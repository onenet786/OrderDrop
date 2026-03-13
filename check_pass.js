const bcrypt = require('bcryptjs');
const hash = '$2a$10$H0bv4VbeTF5Bj4EJi92aQ.R338RGs4E7ELP780xTVmEfSYZS2jCBi';
console.log('Match:', bcrypt.compareSync('123456', hash));
