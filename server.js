const express = require('express');
const http = require('http');
const path = require('path');
const { Server } = require('socket.io');

const MIN = 1.0, MAX = 999.999;
const app = express();
app.use(express.static(path.join(__dirname, 'public')));
app.get('/health', (_req, res) => res.json({ ok: true, app: 'walkie' }));
const io = new Server(http.createServer(app).listen(process.env.PORT || 3000));

const speakers = {}; // room -> socket id currently talking
const roomOf = (s) => s.data.room;

function leave(socket) {
  const room = roomOf(socket);
  if (!room) return;
  if (speakers[room] === socket.id) {
    delete speakers[room];
    io.to(room).emit('speaker', null);
  }
  socket.leave(room);
  socket.to(room).emit('peer-left', socket.id);
  socket.data.room = null;
}

io.on('connection', (socket) => {
  socket.on('join', (freq, cb) => {
    if (typeof cb !== 'function') cb = null;
    const f = Math.round(parseFloat(freq) * 1000) / 1000;
    if (!(f >= MIN && f <= MAX)) return cb && cb({ error: `Frequency ${MIN.toFixed(3)}-${MAX.toFixed(3)} ke beech honi chahiye` });
    leave(socket);
    const room = 'freq-' + f.toFixed(3);
    const peers = [...(io.sockets.adapter.rooms.get(room) || [])];
    socket.join(room);
    socket.data.room = room;
    cb && cb({ freq: f.toFixed(3), peers, count: peers.length + 1, speaker: speakers[room] || null });
    socket.to(room).emit('peer-joined', socket.id);
  });

  socket.on('signal', (msg) => {
    if (msg && typeof msg.to === 'string') io.to(msg.to).emit('signal', { from: socket.id, data: msg.data });
  });

  // Ack callback is always the last argument (mobile clients also send a data arg)
  socket.on('ptt-start', (...args) => {
    const cb = typeof args[args.length - 1] === 'function' ? args[args.length - 1] : () => {};
    const room = roomOf(socket);
    if (!room || (speakers[room] && speakers[room] !== socket.id)) return cb(false);
    speakers[room] = socket.id;
    io.to(room).emit('speaker', socket.id);
    cb(true);
  });

  socket.on('ptt-stop', () => {
    const room = roomOf(socket);
    if (room && speakers[room] === socket.id) {
      delete speakers[room];
      io.to(room).emit('speaker', null);
    }
  });

  socket.on('disconnecting', () => leave(socket));
});

process.on('uncaughtException', (e) => console.error('uncaught:', e));
console.log('Walkie running on http://localhost:' + (process.env.PORT || 3000));
