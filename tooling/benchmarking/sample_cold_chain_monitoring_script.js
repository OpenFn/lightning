// This script is used to load test a sample cold chain monitoring job.
// It sends an array of 500 objects, each representing  measurement from
// an imaginary cold-chain system.
// Depending on your needs, you can process it on your test instance by
// creating a job similar to the below:
//
// fn(state => {
//
//   let attempts = [1,2,3,4];
//
//   attempts.forEach(function (_counter, _index) {
//     state.data.records.forEach(function (record, _index) {
//       console.log(record);
//     }); 
//   });
//
//   return new Promise((resolve, reject) => {
//     setTimeout(() => {
//       resolve(state);
//     }, 10000);
//   });
//   
// });
// 
// The above job will 'process' each of the objects in the array and then
// pause for 10 seconds before proceeding.

import http from 'k6/http';
import { check } from 'k6';

const webhookURL = __ENV.WEBHOOK_URL

export const options = {
  discardResponseBodies: true,
  scenarios: {
    coldChainMonitoring: {
      executor: 'constant-arrival-rate',
      duration: '180s',
      rate: 3,
      timeUnit: '2s',
      preAllocatedVUs: 50,
    },
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
  let records = [];

  let base_timestamp = 1713350530;
  let base_temperature = 3.0;

  for (var i = 0; i < 500; i++) {
    let time = base_timestamp + i;
    let temperature = base_temperature + i/1000.0;

    records.push({temperature: temperature, time: time})
  }

  return {
    payload: {
      records: records
    }
  };
}

export default function (data) {
  const payload = JSON.stringify(data.payload);
  const headers = { 'Content-Type': 'application/json' };
  const res = http.post(webhookURL, payload, { headers });
  check(res, { 'status was 200': r => r.status == 200 });
}
