const path = require('path');

module.exports = function(app) {
    app.get('/', function(req, res) {
        res.sendFile(
            path.join(__dirname, 'server/views/index.html')
        );
    });

    app.get('/health', function(req, res) {
        res.status(200).json({
            status: 'healthy',
            service: 'cloud-operations-platform',
            timestamp: new Date().toISOString()
        });
    });
};
