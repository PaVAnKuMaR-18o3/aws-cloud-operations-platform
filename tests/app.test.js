const request = require('supertest');
const app = require('../app/app');

describe('Cloud Operations Platform', () => {
    describe('GET /', () => {
        test('returns HTTP 200', async () => {
            const response = await request(app).get('/');

            expect(response.statusCode).toBe(200);
        });

        test('returns HTML content', async () => {
            const response = await request(app).get('/');

            expect(response.headers['content-type']).toMatch(/html/);
        });

        test('renders the expected homepage title and content', async () => {
            const response = await request(app).get('/');

            expect(response.text).toContain(
                '<title>Sample Node.js Application</title>'
            );
            expect(response.text).toContain(
                '<span>Sample Node.js Application</span>'
            );
        });
    });

    describe('GET /health', () => {
        test('returns HTTP 200 and healthy status', async () => {
            const response = await request(app).get('/health');

            expect(response.statusCode).toBe(200);
            expect(response.body.status).toBe('healthy');
            expect(response.body.service).toBe(
                'cloud-operations-platform'
            );
        });

        test('returns a valid ISO timestamp', async () => {
            const response = await request(app).get('/health');
            const timestamp = response.body.timestamp;

            expect(typeof timestamp).toBe('string');
            expect(timestamp).toMatch(
                /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/
            );
            expect(Number.isNaN(Date.parse(timestamp))).toBe(false);
            expect(new Date(timestamp).toISOString()).toBe(timestamp);
        });
    });
});
