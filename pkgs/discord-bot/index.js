// Copyright 2023 HALBY
// See LICENSE file for details.

import { spawn, exec } from 'child_process';
import fs from 'fs';
import { Writable } from 'stream';

// ビルドするパッケージ名
const packageName = 'web';

// Discord.jsライブラリの読み込み
import pkg from 'discord.js';
const { Client, GatewayIntentBits } = pkg;

// Discordクライアントのインスタンスを作成
const client = new Client({
    intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.GuildMessages,
        GatewayIntentBits.MessageContent
    ]
});

// Discordにログインする準備ができたときに実行されるイベント
client.once('ready', () =>
{
    console.log('Logged in as ' + client.user?.tag);
});

let isRunning = false;

const BOT_NOTIFY_PREFIX = '[BOT_NOTIFY]';

/**
 * コマンドを実行する
 * @param {string} command
 * @param {function(number | null, string, string): void | Promise<void>} callback
 * @param {function(string): void} internalErrorCallback
 * @param {function(string): void | null} notifyCallback [BOT_NOTIFY]マーカー検出時に呼ばれるコールバック
 */
function runTask(command, callback, internalErrorCallback, notifyCallback = null)
{
    if (isRunning)
    {
        console.log('既にビルドプロセスが実行中です。');
        internalErrorCallback('既にビルドプロセスが実行中です。\n処理を中止します。');
        return;
    }
    isRunning = true;
    if (fs.existsSync('logs') === false)
    {
        fs.mkdirSync('logs');
    }
    const logFileName = `logs/${ command }-log-${ Date.now() }.txt`;
    const logErrStream = new CustomWritableStream(); // stderrのみ保持（Discord通知用）
    const logFileStream = fs.createWriteStream(logFileName, { flags: 'a' });

    // pnpmを使用してビルドタスクを実行
    const buildProcess = spawn('pnpm', [ 'run', '--filter', packageName, command ]);

    // 標準出力・標準エラー出力をともにファイルに書き込む
    buildProcess.stdout.pipe(logFileStream, { end: false });
    buildProcess.stderr.pipe(logFileStream, { end: false });
    // stderrはDiscord通知用にメモリにも保持する
    buildProcess.stderr.pipe(logErrStream, { end: false });

    // 標準エラーのログをリアルタイムでコンソールに出力し、[BOT_NOTIFY]マーカーを検出する
    let stderrBuffer = '';
    let lastNotifiedMessage = '';
    let debounceTimer = null;
    buildProcess.stderr.on('data', (data) =>
    {
        const text = data.toString();
        console.error(text);

        if (notifyCallback)
        {
            stderrBuffer += text;
            const lines = stderrBuffer.split('\n');
            stderrBuffer = lines.pop(); // 末尾の不完全な行をバッファに戻す
            for (const line of lines)
            {
                const idx = line.indexOf(BOT_NOTIFY_PREFIX);
                if (idx === -1) continue;
                const notifyMsg = line.slice(idx + BOT_NOTIFY_PREFIX.length).trim();
                if (!notifyMsg || notifyMsg === lastNotifiedMessage) continue;
                lastNotifiedMessage = notifyMsg;
                clearTimeout(debounceTimer);
                debounceTimer = setTimeout(() =>
                {
                    notifyCallback(notifyMsg);
                    lastNotifiedMessage = '';
                }, 5000);
            }
        }
    });

    buildProcess.on('exit', (code) =>
    {
        logErrStream.end(); // ログストリームを閉じる
        logFileStream.end(); // ログストリームを閉じる
        console.log(`ビルドが終了しました。終了コード: ${ code }`);
        isRunning = false;

        // Discordのメッセージ上限(2000文字)に収まるよう末尾1800文字に切り詰める
        const errText = logErrStream.data.slice(-1800);
        callback(code, errText, logFileName);
    });
}

/**
 * カスタムWritableストリーム。
 * 受け取ったデータを内部変数に文字列として保持します。
 * 
 * @extends Writable
 */
class CustomWritableStream extends Writable
{
    /**
     * CustomWritableStreamのインスタンスを作成します。
     * @param {Object} [options] ストリームオプション
     */
    constructor(options)
    {
        super(options);
        /** @type {string} 内部に保持するデータ */
        this.data = '';
    }

    /**
     * ストリームにデータが書き込まれるときに呼ばれます。
     * 
     * @param {Buffer|string} chunk 書き込まれるデータのチャンク
     * @param {string} encoding チャンクのエンコーディング（バッファの場合は 'buffer'）
     * @param {Function} callback コールバック関数（エラーがある場合に呼び出す）
     */
    _write(chunk, encoding, callback)
    {
        this.data += chunk.toString();
        callback();
    }
}


// メッセージがサーバーに送信されたときに実行されるイベントハンドラ
client.on('messageCreate', message =>
{
    // ボット自身が送信したメッセージやDMへの応答を避ける
    if (!message.guild || message.author.bot) return;

    // @everyoneや@hereメンションには反応しない
    if (message.mentions.everyone) return;

    // メンションが含まれているか確認する
    if (client.user && message.mentions.has(client.user.id))
    {
        // メッセージの内容から、コマンド部分を取り出す（例：'!ping'の'ping'）
        // プレフィックスを使わない場合は、メンション部分を除去して解析する
        const content = message.content.replace(/<@!?(\d+)>/, '').trim();
        const args = content.split(/\s+/); // 空白で引数を区切る
        const command = args.shift()?.toLowerCase() ?? ''; // コマンド名を取得

        const builds = [ 'build', 'build-dev', 'build-staging' ];
        const deploys = [ 'deploy', 'deploy-dev', 'deploy-staging' ];
        const buildDeploys = [ 'build-deploy', 'build-deploy-dev', 'build-deploy-staging' ];
        // コマンド名に応じた処理を行う
        if (command === 'ping')
        {
            message.channel.send('Pong!');
        } else if (command === 'hello')
        {
            message.channel.send('こんにちは！');
        } else if (builds.includes(command))
        {
            message.channel.send('ビルドを開始します…');

            runTask(command, async (code, error, logFileName) =>
            {
                console.log(message);
                console.log(`ビルドプロセスが終了しました。終了コード: ${ code }`);
                if (code === 0)
                {
                    await message.channel.send(`ビルドプロセスが正常に終了しました。`);
                } else
                {
                    await message.channel.send(`ビルドプロセスが異常終了しました。`);
                    await message.channel.send(`\`\`\`${ error }\`\`\``);
                    await message.channel.send(`詳細は添付のログを参照してください。`);
                    // ログファイルをDiscordにアップロード
                    message.channel.send({ files: [ logFileName ] }).catch(console.error);
                }
            }, (error) => message.channel.send(error),
            (notifyMsg) => message.channel.send(notifyMsg).catch(console.error));
        } else if (deploys.includes(command))
        {
            message.channel.send('デプロイを開始します…');

            runTask(command, (code) =>
            {
                console.log(`デプロイプロセスが終了しました。`);
                message.channel.send(`デプロイプロセスが終了しました。`);
            }, (error) => message.channel.send(error));
        } else if (buildDeploys.includes(command))
        {

            message.channel.send('ビルドとデプロイを開始します…');

            runTask(command, async (code, error, logFileName) =>
            {
                console.log(`ビルドプロセスが終了しました。終了コード: ${ code }`);
                if (code === 0)
                {
                    await message.channel.send(`ビルドプロセスが正常に終了しました。`);
                } else
                {
                    await message.channel.send(`ビルドプロセスが異常終了しました。`);
                    await message.channel.send(`\`\`\`${ error }\`\`\``);
                    await message.channel.send(`詳細は添付のログを参照してください。`);
                    // ログファイルをDiscordにアップロード
                    message.channel.send({ files: [ logFileName ] }).catch(console.error);
                }
            }, (error) => message.channel.send(error),
            (notifyMsg) => message.channel.send(notifyMsg).catch(console.error));
        } else if (command === 'help')
        {
            message.channel.send(`\`\`\`
                こんにちは！私はとまりぎ亭Web管理BOTです！
                このBOTでは、メンションのあとに特定のコマンドをつけることでWebページを管理するためのタスクを実行することができます。
                
                コマンドの一覧:
                "help" ... このコマンドです。コマンド一覧を紹介します。
                "build-dev" ... Webページ(開発版)のビルド処理を行います。アップロードは行いません。
                "deploy-dev" ... Webページ(開発版)のアップロードを行います。ビルド処理は行いません。
                "build-deploy-dev" ... Webページ(開発版)のビルドとアップロードを行います。
                "build-staging" ... Webページ(ステージング版)のビルド処理を行います。アップロードは行いません。
                "deploy-staging" ... Webページ(ステージング版)のアップロードを行います。ビルド処理は行いません。
                "build-deploy-staging" ... Webページ(ステージング版)のビルドとアップロードを行います。
                "build" ... Webページ(本番版)のビルド処理を行います。アップロードは行いません。
                "deploy" ... Webページ(本番版)のアップロードを行います。ビルド処理は行いません。
                "build-deploy" ... Webページ(本番版)のビルドとアップロードを行います。
                
                備考:
                -devのつくコマンドは開発版に対する処理です。このバージョンではダミーデータが使用されています。
                -stagingのつくコマンドはステージング版に対する処理です。このバージョンでは本番用のデータが使用されています。
                開発版Webページとステージング版Webページは、それぞれ下記URLからアクセスすることができます。
                https://tomarigitei.com/test-dev/
                https://tomarigitei.com/test-staging/
                認証用のIDとパスワードは、従来のテストページと同じものです。
                \`\`\``.replace(/(^ +)/gm, '')
            );
        } else
        {
            // 既知のコマンドに該当しない場合の処理
            message.channel.send(`こんにちは！私はとまりぎ亭Web管理BOTです！
                このBOTは定型文による自動応答のため、会話はできません。
                このBOTの機能について知りたい場合、「help」とメンションしてください。`.replace(/(^\s+|\s+$)/gm, ''));
        }
    }
});

// あなたのBotトークンをここに置く
client.login(process.env.BOT_TOKEN);