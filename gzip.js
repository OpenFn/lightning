import { gzipSync } from "node:zlib";
const url = "http://localhost:4000/i/ab1801c2-3af0-40cf-8f0c-b743a0afce9b";

const json = {
  traitors: ["alan"],
  faithfuls: ["david"],
};

const gzippedData = gzipSync(Buffer.from(JSON.stringify(json)));

// Post with fetch
const response = await fetch(url, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Content-Encoding": "gzip",
  },
  body: gzippedData,
});

console.log("Status:", response.status);
console.log("Response:", await response.text());
