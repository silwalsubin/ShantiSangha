namespace ShantiSangha.Friends.Models;

/// Coarse relation taxonomy. `Other` lets the user supply a freeform
/// label via `Connection.CustomRelationLabel` for anything outside the
/// common set (yoga teacher, neighbor, ex, mentor, etc.).
public enum ConnectionType
{
    Spouse,
    Parent,
    Sibling,
    Child,
    Friend,
    Colleague,
    Other
}
