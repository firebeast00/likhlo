import http from 'node:http';
import process from 'node:process';
import { WebSocketServer } from 'ws';
import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import speech from '@google-cloud/speech';

const projectId = process.env.GOOGLE_CLOUD_PROJECT;
const location = process.env.CHIRP_LOCATION || 'eu';
const port = Number(process.env.PORT || 8080);

if (!projectId) throw new Error('GOOGLE_CLOUD_PROJECT is required');
if (!getApps().length) initializeApp({ credential: applicationDefault() });

const client = new speech.v2.SpeechClient();
const server = http.createServer((request, response) => {
  if (request.url === '/healthz') {
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(JSON.stringify({ ok: true }));
    return;
  }
  response.writeHead(404).end();
});
const sockets = new WebSocketServer({ noServer: true });

server.on('upgrade', async (request, socket, head) => {
  if (request.url !== '/v1/speech/stream') return socket.destroy();
  const authorization = request.headers.authorization || '';
  const token = authorization.startsWith('Bearer ')
    ? authorization.slice(7)
    : '';
  try {
    await getAuth().verifyIdToken(token, true);
    sockets.handleUpgrade(request, socket, head, (webSocket) => {
      sockets.emit('connection', webSocket);
    });
  } catch {
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
    socket.destroy();
  }
});

sockets.on('connection', (socket) => {
  let recognizeStream;
  let configured = false;

  socket.on('message', (data, isBinary) => {
    if (!configured) {
      if (isBinary) return socket.close(1003, 'Configuration required');
      const message = JSON.parse(data.toString());
      if (message.type !== 'config') return socket.close(1003, 'Invalid config');
      const hints = Array.isArray(message.hints)
        ? message.hints.slice(0, 200).map((value) => ({ value: String(value) }))
        : [];
      recognizeStream = client
        .streamingRecognize()
        .on('data', (response) => {
          for (const result of response.results || []) {
            const alternative = result.alternatives?.[0];
            if (!alternative) continue;
            socket.send(JSON.stringify({
              type: 'transcript',
              text: alternative.transcript || '',
              isFinal: Boolean(result.isFinal),
              stability: result.stability,
              languageCode: result.languageCode,
            }));
          }
        })
        .on('error', (error) => {
          socket.send(JSON.stringify({ type: 'error', message: error.code || 'chirp_error' }));
          socket.close(1011, 'Recognition failed');
        });
      recognizeStream.write({
        recognizer: `projects/${projectId}/locations/${location}/recognizers/_`,
        streamingConfig: {
          config: {
            autoDecodingConfig: {},
            languageCodes: message.languageCodes || ['ur-PK'],
            model: 'chirp_3',
            features: { enableAutomaticPunctuation: true },
            adaptation: hints.length
              ? { phraseSets: [{ inlinePhraseSet: { phrases: hints } }] }
              : undefined,
          },
          streamingFeatures: { interimResults: true },
        },
      });
      configured = true;
      return;
    }

    if (isBinary) recognizeStream?.write({ audio: data });
    else if (JSON.parse(data.toString()).type === 'finish') recognizeStream?.end();
  });

  socket.on('close', () => recognizeStream?.end());
});

server.listen(port, () => {
  console.log(`Likhlo speech gateway listening on ${port}`);
});
