const express = require('express');
const app = express();
const port = 3000;
const host = '0.0.0.0';

app.get('/', (req, res) => {
    res.send('Servidor rodando!');
});

app.listen(port, host, () => {
    console.log(`Servidor rodando em http://${host}:${port}`);
});