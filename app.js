const http = require('http');
const app = require('./app/app');

const port = process.env.PORT || 3000;

const server = http.createServer(app).listen(port, function() {
    console.log('The application is running on port ' + port);
});

module.exports = server;
