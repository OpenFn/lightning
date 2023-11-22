import http from 'k6/http';
import { check } from 'k6';

const webhookURL =
  'http://localhost:4000/i/cae544ab-03dc-4ccc-a09c-fb4edb255d7a';

export const options = {
  discardResponseBodies: true,
  scenarios: {
    webhookRequests: {
      executor: 'ramping-arrival-rate',
      startRate: 1,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      stages: [
        { duration: '30s', target: 50 }, // go from 1 to 50 rps in the first 30 seconds
        { duration: '1m30s', target: 50 }, // hold at 50 rps for 1.5 minutes
        { duration: '20s', target: 0 }, // ramp down back to 0 rps over the last 30 seconds
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.0001'], // http errors should be less than 0.01%
    http_req_duration: [
      'p(95)<250', // 95% of requests should be below 250ms
      'p(99)<400', // 99% of requests should be below 400ms
    ],
  },
};

export function setup() {
  let payload_size = 10;

  if (__ENV.PAYLOAD_SIZE != null) {
    payload_size = parseInt(__ENV.PAYLOAD_SIZE, 10) * 1000;
  }

  return {
    payload: {
      name: 'lorem',
      surname: 'ipsum',
      data: '0123456789'.repeat(payload_size / 10), // Repeating string is 10 bytes in size
    },
  };
}

export default function (data) {
  const payload = JSON.stringify(data.payload);
  const headers = { 'Content-Type': 'application/json' };
  const res = http.post(webhookURL, payload, { headers });
  check(res, { 'status was 200': r => r.status == 200 });
}
