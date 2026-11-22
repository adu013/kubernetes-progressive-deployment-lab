const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const os = require('os');

const app = express();
app.use(cors());
app.use(express.json());

const mongoUri = process.env.MONGO_URI || 'mongodb://mongo-service:27017/merndb';
mongoose.connect(mongoUri).then(() => console.log('Connected to MongoDB'));

const Item = mongoose.model('Item', new mongoose.Schema({ text: String }));

app.get('/api/items', async (req, res) => {
  const items = await Item.find();
  res.json({ pod: os.hostname(), items });
});

app.post('/api/items', async (req, res) => {
  const item = await Item.create({ text: req.body.text });
  res.json(item);
});

app.listen(5000, () => console.log('Backend running on port 5000'));
