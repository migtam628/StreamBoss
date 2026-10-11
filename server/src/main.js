import { createApp, VERSION } from './app.js';

const port = Number(process.env.PORT ?? 8080);
const app = createApp();
app.server.listen(port, () => {
  console.log(`StreamBoss sync ${VERSION} listening on :${port} (registration: ${process.env.REGISTRATION ?? 'first'})`);
});
for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => app.close().then(() => process.exit(0)));
}
