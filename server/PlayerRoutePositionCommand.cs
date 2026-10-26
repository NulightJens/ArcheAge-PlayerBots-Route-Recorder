using System.Globalization;
using AAEmu.Game.Core.Managers;
using AAEmu.Game.Models.Game;
using AAEmu.Game.Models.Game.Char;
using AAEmu.Game.Utils.Scripts;

namespace AAEmu.Game.Scripts.Commands;

/// <summary>
/// Exposes the invoking player's server-owned transform as a small, stable payload for
/// the local route recorder. This command is read-only and intentionally does not look
/// up another character or inspect client memory.
/// </summary>
public sealed class PlayerRoutePositionCommand : ICommand
{
    public const string PayloadPrefix = "PLAYER_ROUTE_SAMPLE_V1 ";

    public string[] CommandNames { get; set; } = ["playerrouteposition"];

    public void OnLoad()
    {
        CommandManager.Instance.Register(CommandNames, this);
    }

    public string GetCommandLineHelp() => "sample";

    public string GetCommandHelpText() =>
        "Returns your current server-side transform for the local PlayerBots route recorder.";

    public void Execute(Character character, string[] args, IMessageOutput messageOutput)
    {
        if (character?.Transform == null)
        {
            CommandManager.SendErrorText(this, messageOutput, "Player transform is unavailable.");
            return;
        }

        var position = character.Transform.World.Position;
        if (!float.IsFinite(position.X) || !float.IsFinite(position.Y) || !float.IsFinite(position.Z))
        {
            CommandManager.SendErrorText(this, messageOutput, "Player transform contains a non-finite position.");
            return;
        }

        CommandManager.SendNormalText(
            this,
            messageOutput,
            PayloadPrefix + FormatPayload(character, DateTimeOffset.UtcNow));
    }

    internal static string FormatPayload(Character character, DateTimeOffset capturedUtc)
    {
        ArgumentNullException.ThrowIfNull(character);
        ArgumentNullException.ThrowIfNull(character.Transform);

        var transform = character.Transform;
        var world = transform.World;
        var position = world.Position;
        var heading = world.Rotation.Z;
        var headingJson = float.IsFinite(heading)
            ? heading.ToString("R", CultureInfo.InvariantCulture)
            : "null";
        var timestamp = capturedUtc.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture);

        return string.Create(
            CultureInfo.InvariantCulture,
            $"{{\"schemaVersion\":1,\"capturedUtc\":\"{timestamp}\",\"worldId\":{transform.WorldId}," +
            $"\"instanceId\":{transform.InstanceId},\"zoneId\":{transform.ZoneId}," +
            $"\"x\":{position.X:R},\"y\":{position.Y:R},\"z\":{position.Z:R}," +
            $"\"headingRadians\":{headingJson},\"quality\":\"authoritative-server-transform\"," +
            $"\"source\":\"aaemu-loopback-command-v1\"}}");
    }
}
