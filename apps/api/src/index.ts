import express from 'express'
import cors from 'cors'
import { startServer } from './server';
import { notificationsRouter } from "./notifications/notifications.router";

const app = express();

app.use(cors());
app.use(express.json());
app.use("/api/notifications", notificationsRouter);

app.get('/api/health', (_req, res) => {
    res.json({ status: 'ok', runtime: 'express' });
});

console.log({a: process.env.PORT, b: process.env.NOVU_SECRET_KEY})

startServer().then((port) => {
    app.listen(port, () => {
        console.log(`info. API backend actively listening on http://localhost:${port}`);
    });
});