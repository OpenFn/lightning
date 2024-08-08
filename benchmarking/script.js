import http from 'k6/http';
import { check } from 'k6';

const webhookURL =
  __ENV.WEBHOOK_URL ||
  'https://demo.openfn.org/i/cae544ab-03dc-4ccc-a09c-fb4edb255d7a';

export const options = {
  discardResponseBodies: true,
  scenarios: {
    // test: {
    //   executor: 'constant-arrival-rate',
    //   rate: 1,
    //   timeUnit: '1s',
    //   duration: '1s',
    //   preAllocatedVUs: 100,
    // },
    open_model: {
      executor: 'constant-arrival-rate',
      rate: 50,
      timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 100,
    },
    // webhookRequests: {
    //   executor: 'ramping-arrival-rate',
    //   startRate: 1,
    //   timeUnit: '1s',
    //   preAllocatedVUs: 500,
    //   stages: [
    //     { duration: '30s', target: 50 }, // go from 1 to 50 rps in the first 30 seconds
    //     { duration: '1m30s', target: 50 }, // hold at 50 rps for 1.5 minutes
    //     { duration: '20s', target: 0 }, // ramp down back to 0 rps over the last 30 seconds
    //   ],
    // },
  },
  thresholds: {
    http_req_failed: ['rate<0.0001'], // http errors should be less than 0.01%
    http_req_waiting: [
      'p(95)<250', // 95% of requests should wait less than 250ms
      'p(99)<400', // 99% of requests should wait less than 400ms
    ],
  },
};

export function setup() {
  let payload_size_kb = 2;

  if (__ENV.PAYLOAD_SIZE_KB != null) {
    payload_size_kb = parseInt(__ENV.PAYLOAD_SIZE_KB, 10);
  }

  return {
    payload: {
      name: 'lorem',
      surname: 'ipsum',
      data: '0123456789'.repeat((payload_size_kb * 1000) / 10), // Repeating string is 10 bytes in size
    },
  };
}

export default function (data) {
  const payload = JSON.stringify(data.payload);
  const headers = { 'Content-Type': 'application/json' };
  const res = http.post(webhookURL, payload, { headers });
  if (res.status != 200)
    console.log(
      res.status,
      res.status_text,
      res.body,
      res.error,
      res.error_code
    );
  check(res, { 'status was 200': r => r.status == 200 });
}
