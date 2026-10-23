const request = require('supertest');
const app = require('../app/app');

describe('Cloud Operations Platform', () => {
    test('GET / returns HTTP 200', async () => {
        const response = await request(app).get('/');
        expect(response.statusCode).toBe(200);
    });

    test('GET /health returns healthy status', async () => {
        const response = await request(app).get('/health');

        expect(response.statusCode).toBe(200);
        expect(response.body.status).toBe('healthy');
        expect(response.body.service).toBe('cloud-operations-platform');
        expect(response.body.timestamp).toBeDefined();
    });
});
