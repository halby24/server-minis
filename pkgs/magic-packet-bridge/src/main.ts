import express from "express";
import dgram from "dgram";
import 'dotenv/config';

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const LISTEN_PORT = process.env.LISTEN_PORT;
const MAGIC_PACKET_PORT = Number(process.env.MAGIC_PACKET_PORT);

const socket = dgram.createSocket('udp4');

socket.on('listening', () => 
{
    socket.setBroadcast(true);
});

app.listen(LISTEN_PORT, () => 
{
    console.log('サーバー起動中');
});

const sendMagicPacket = (macAddr: string, res: express.Response) =>
{
    const macAddrNumArr = macAddr.match(/.{2}/g)?.map(str => parseInt(str, 16));

    if (!macAddrNumArr)
    {
        res.write('MACアドレスが正しくありません');
        res.end();
        return;
    }

    const buf = new Uint8Array(102);
    let bytes = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, ];
    for (let i = 0; i < 16; i++)
    {
        bytes = bytes.concat(macAddrNumArr);
    }
    buf.set(bytes);

    socket.send(buf, 0, buf.length, MAGIC_PACKET_PORT, '255.255.255.255', (err, _) =>
    {
        if (!err)
        {
            const msg = `${macAddr}へのMagic Packetの送信に成功しました`;
            console.log(msg);
            res.send(msg);
        }
        else
        {
            res.send(err.message);
        }
    });
};

app.post('/', (req, res) =>
{
    const macAddr: string | undefined = req.body?.mac;

    if (!macAddr)
    {
        res.write('MACアドレスのパラメータがありません');
        res.end();
        return;
    }

    sendMagicPacket(macAddr, res);
});