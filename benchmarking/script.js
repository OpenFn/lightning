import http from 'k6/http';
import { check } from 'k6';

const webhookURL =
  'http://localhost:4000/i/9102044d-0976-40ad-87a2-b15728346500';

const requestsNumber = 10;

export const options = {
  vus: requestsNumber,
  stages: [
    { duration: '30s', target: 100 },
    { duration: '1m30s', target: 50 },
    { duration: '20s', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'], // http errors should be less than 1%
    http_req_duration: ['p(95)<200'], // 95% of requests should be below 200ms
  },
};

export default function () {
  const payload = JSON.stringify({
    name: 'lorem',
    surname: 'ipsum',
  });
  const headers = { 'Content-Type': 'application/json' };
  http.post(webhookURL, payload, { headers });
  check(res, { 'status was 200': r => r.status == 200 });
}
