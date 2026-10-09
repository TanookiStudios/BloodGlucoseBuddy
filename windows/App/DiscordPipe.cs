using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using BloodGlucoseBuddy.Core;

namespace BloodGlucoseBuddy;

sealed class DiscordException(string message) : Exception(message);

/// <summary>Talks to the Discord desktop app over its local named pipe (the Rich Presence "IPC" protocol).
/// Not thread-safe: the caller serializes access.</summary>
sealed class DiscordPipe(string clientId) : IDisposable
{
    private static readonly TimeSpan ReplyTimeout = TimeSpan.FromSeconds(5);
    private NamedPipeClientStream? pipe;

    /// <summary>Passing null clears the status.</summary>
    public void SetActivity(Dictionary<string, object>? activity)
    {
        if (pipe is not { IsConnected: true }) Connect();
        try
        {
            var args = new Dictionary<string, object> { ["pid"] = Environment.ProcessId };
            if (activity is not null) args["activity"] = activity;
            Send(1, new Dictionary<string, object> { ["cmd"] = "SET_ACTIVITY", ["args"] = args, ["nonce"] = Guid.NewGuid().ToString() });
            var (op, reply) = Receive();
            if (op == 2) throw new DiscordException("Lost the connection to Discord.");
            if (reply.TryGetProperty("evt", out var evt) && evt.GetString() == "ERROR")
            {
                var message = reply.TryGetProperty("data", out var d) && d.TryGetProperty("message", out var m) ? m.GetString() : "unknown error";
                throw new DiscordException($"Discord said: {message}");
            }
        }
        catch
        {
            Close();
            throw;
        }
    }

    private void Connect()
    {
        Close();
        for (var i = 0; i < 10; i++)
        {
            var p = new NamedPipeClientStream(".", $"discord-ipc-{i}", PipeDirection.InOut, PipeOptions.Asynchronous);
            try { p.Connect(300); }
            catch (Exception e) when (e is TimeoutException or IOException) { p.Dispose(); continue; }
            pipe = p;
            try
            {
                Send(0, new Dictionary<string, object> { ["v"] = 1, ["client_id"] = clientId });
                var (op, reply) = Receive();
                if (op == 2) throw new DiscordException($"Discord said: {(reply.TryGetProperty("message", out var m) ? m.GetString() : "connection refused")}");
                if (!(reply.TryGetProperty("evt", out var evt) && evt.GetString() == "READY")) throw new DiscordException("Unexpected reply from Discord.");
                return;
            }
            catch
            {
                Close();
                throw;
            }
        }
        throw new DiscordException("Discord isn't open.");
    }

    private void Send(uint opcode, object json)
    {
        var frame = DiscordFrame.Build(opcode, JsonSerializer.SerializeToUtf8Bytes(json));
        pipe!.Write(frame);
        pipe.Flush();
    }

    private (uint, JsonElement) Receive()
    {
        var header = ReadExactly(8);
        var opcode = BitConverter.ToUInt32(header, 0);
        var length = BitConverter.ToUInt32(header, 4);
        if (length > 1_000_000) throw new DiscordException("Lost the connection to Discord.");
        var body = ReadExactly((int)length);
        try { return (opcode, JsonDocument.Parse(body).RootElement.Clone()); }
        catch (JsonException) { return (opcode, JsonDocument.Parse("{}").RootElement.Clone()); }
    }

    private byte[] ReadExactly(int count)
    {
        var buffer = new byte[count];
        using var cts = new CancellationTokenSource(ReplyTimeout);
        try { pipe!.ReadExactlyAsync(buffer, cts.Token).AsTask().GetAwaiter().GetResult(); }
        catch (Exception e) when (e is OperationCanceledException or EndOfStreamException or IOException)
        {
            throw new DiscordException("Lost the connection to Discord.");
        }
        return buffer;
    }

    public void Close()
    {
        pipe?.Dispose();
        pipe = null;
    }

    public void Dispose() => Close();
}
