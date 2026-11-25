// A slow HTTPS server for SnapreelTests/BackgroundSessionProbe: counts how many uploads arrive at the same time, over
// HTTP/2 or HTTP/1.1. Usage: node h2-probe-server.mjs <key.pem> <cert.pem> <port>
import fs from "node:fs";
import http2 from "node:http2";

const [key, cert, port] = process.argv.slice(2);
let open = 0;
let most = 0;
let done = 0;
const versions = {};
const server = http2.createSecureServer({ key: fs.readFileSync(key), cert: fs.readFileSync(cert), allowHTTP1: true });
server.on("request", (req, res) => {
  if (req.url.endsWith("/report")) {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ most, done, versions }));
    return;
  }
  versions[req.httpVersion] = (versions[req.httpVersion] || 0) + 1;
  open += 1;
  most = Math.max(most, open);
  let closed = false;
  const close = () => {
    if (!closed) open -= 1;
    closed = true;
  };
  // About 1 MB/s each.
  req.on("data", (d) => {
    req.pause();
    setTimeout(() => req.resume(), Math.ceil((d.length / 1_000_000) * 1000));
  });
  req.on("end", () => {
    done += 1;
    close();
    res.writeHead(200, { etag: '"probe"' });
    res.end();
  });
  req.on("close", close);
  req.on("error", close);
});
server.listen(Number(port), () => console.log(`listening on ${port}`));
