# Stubes

~~An attempt to be Luanti's best item transport.~~
### After 2 months: Turns out, perfectionism is how you *kill* a project... some non-trivial visual bugs that sound more like a leetcode problem are okay.

An attempt to be a decent solution to transportation of ItemStacks in Luanti.

**I encourage you to fork this project and make a more generic version not limited to ItemStacks, and make it better**


I am using 32x32 textures for the tubes, because i could not fit a recognizable arrow into a 32x32 texture without making the node bigger.
I am also doing the textures in the style of Skyblock Zero. PRs for textures for other games are welcome.

This mod was inspired by the [Pipeworks Luanti mod](http://github.com/mt-mods/pipeworks) and by the [Mindustry game](https://github.com/Anuken/Mindustry).

## Terminology
In-game, Stubes should refer to themselves as just item tubes, but in code/comparisons they should be referred to as stubes to distinguish them from other implementations of item tubes.

## Compatibility
STubes **don't** implement their own way of letting nodes accept stube tubed items.  
The preffered way for a node to accept STube tubed items is using pipeworks, but there will be other ways in the future.

| Name            | Status            | Notes                                                                                      |
| --------------- | ----------------- | ------------------------------------------------------------------------------------------ |
| **Pipeworks**   | Fully compatible  | Recommended way to make receivers for STubes. Even supports item input to pipeworks tubes. |
| Tubelib         | Not compatible    | PRs welcome! Although i am unsure if there is demand.                                      |
| Others?         | Not compatible    | Let me know if there is anything else worth adding to this table                           |

This library has an API that should make it easy for other mods to be compatible with it. 

### MAJOR INTERNAL IMPROVEMENTS/INTERNAL-ONLY BREAKING CHANGES ARE WELCOME

If you don't think therere is no need for internal restructuring/breaking changes, make an issue.

## Performance
- Tubed item visuals which aren't near the player aren't shown (so that gets rid of the need to perform costly `move_to` calls)
- It should be able to handle 10 000 item stacks easily

# API: TODO
