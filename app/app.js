const express = require('express');
const path = require('path');

const app = express();

app.set('port', process.env.PORT || 3000);
app.set('views', path.join(__dirname, 'server/views'));

app.use(express.static(path.join(__dirname, 'public')));

require('./routes')(app);

module.exports = app;
