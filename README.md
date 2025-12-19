# Die Shrink

**This mod is currently in Alpha testing. Bugs may be present. Beware!**

Die Shrink allows the creation of Integrated Circuits, which are small combinators that contain an internal circuit network. This network can contain many combinators, and interfaces with external circuitry through a set of I/O pins.

## Compact Circuits

Die Shrink came about due to some issues I found in the otherwise very excellent Compact Circuits mod. These issues are very difficult to fix within the mod's architecture. I originally considered submitting an overhaul patch to Compact Circuits until I realized the patch was basically rewriting the whole mod.

Since a rewrite was basically inevitable I decided to take the opportunity to trim away some stuff I thought was unnecessary while I was at it.

Bottom line, Compact Circuits is an excellent mod and if you are happy with it you should use it. However, if any of the following changes appeal to you, you may want to consider Die Shrink as well:

### Differences from Compact Circuits
- **No-frills minimalism** - Die Shrink just shrinks circuits. It does not include the wireless router, interplanetary logistics, models, or display output features of Compact Circuits. If you need these things, use Compact Circuits.

- **Occam's razored** - Die Shrink only adds one buildable entity, which is a 1x1 integrated circuit with 13 I/O pins.

- **Improved blueprint support** - Compact Circuits has several difficult-to-fix bugs around flipping and rotating blueprints. This effectively makes it impossible to e.g. flip a blueprint containing a compact circuit. Overlapping a processor with another also fails in CC. Die Shrink is Things-based and fixes these issues.

- **Remote-view editor** - Editing the inside of an IC uses the remote view rather than teleporting the player character to the editing surface.

- **Always packed** - Die Shrink ICs are always in what Compact Circuits calls "packed mode."

## Credits

## Contributing

Please use the [GitHub repository](https://github.com/wcjohnson/die-shrink) for questions, bug reports, or pull requests.
