// ============================================================================
//  VR dual-wield variant classes.
//
//  Each is a thin, distinct subclass of a base firearm. A SEPARATE class is what
//  lets the engine tell two of one gun apart -- weapon selection is by class, so
//  two instances of ONE class are indistinguishable (unselectable, un-bankable).
//  A "_2" variant is independently selectable AND hand-assignable, and
//  WeaponsMatch(base, variant) is false so MoveWeaponToHand no longer collapses them.
//
//  PlayerPawn.VR_GiveDualWield spawns the "<base>_2" class on the second pickup.
//  These MUST stay empty (no Ammo/Default overrides): inheriting the base means the
//  variant shares the base's reserve ammo pool and (for the 7 archetype-mapped guns:
//  Shotgun/SSG/Pistol/Chaingun/RocketLauncher/PlasmaRifle/BFG) renders the base's 3D
//  model for FREE via FVRWeaponResolver's inheritance-based archetype substitution.
//  The 5 non-archetype guns (Revolver/Rifle/SMG/M79/Flamethrower) get their model
//  from a cloned "Model <name>_2" stanza in modeldef.txt.
//
//  Shotgun_2 is defined in weaponshotgun.zs (do NOT redeclare it here).
//  Scales to _3.._N by the same one-line pattern once a native auto-mint replaces this.
// ============================================================================

class SuperShotgun_2 : SuperShotgun {}
class Chaingun_2     : Chaingun     {}
class Pistol_2       : Pistol       {}
class PlasmaRifle_2  : PlasmaRifle  {}
class BFG9000_2      : BFG9000      {}
class RocketLauncher_2 : RocketLauncher {}
class Revolver_2     : Revolver     {}
class Rifle_2        : Rifle        {}
class SMG_2          : SMG          {}
class M79_2          : M79          {}
class Flamethrower_2 : Flamethrower {}
