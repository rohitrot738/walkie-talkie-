const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const MIN = 1.0, MAX = 999.9;
const app = express();
app.use(express.static('public'));
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
    const f = Math.round(parseFloat(freq) * 10) / 10;
    if (!(f >= MIN && f <= MAX)) return cb && cb({ error: `Frequency ${MIN}-${MAX} ke beech honi chahiye` });
    leave(socket);
    const room = 'freq-' + f.toFixed(1);
    const peers = [...(io.sockets.adapter.rooms.get(room) || [])];
    socket.join(room);
    socket.data.room = room;
    cb && cb({ freq: f.toFixed(1), peers, count: peers.length + 1, speaker: speakers[room] || null });
    socket.to(room).emit('peer-joined', socket.id);
  });

  socket.on('signal', ({ to, data }) => io.to(to).emit('signal', { from: socket.id, data }));

  socket.on('ptt-start', (cb) => {
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

console.log('Walkie running on http://localhost:' + (process.env.PORT || 3000));
