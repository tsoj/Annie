cd d##### Generate positions
```
nim c --run generatePositions.nim
```

##### Remove non-quiet positions

```
nim c --run removeNonQuietPositions.nim
```

##### Merge duplicates and select random subset
```
nim c --run mergeDuplicateAndSelect.nim
```

##### Label positions

Create an empty file called `quietSetNalwald.epd`.

```
mv quietSetNalwald.epd quietSetNalwald.epd.backup
touch quietSetNalwald.epd
```

Install [Psutil-Nim](https://github.com/johnscillieri/psutil-nim).

```
nimble install psutil
```

Label positions.

```
nim c --run labelPositions.nim
```

##### Run optimization
```
nim c --run optimization.nim
```

##### Get piece values
```
nim c --run calculatePieceValue.nim
```

##### How data sets are generated

###### quietSetZuri.epd

- quiet set from the Zurichess engine

###### quietSetNalwald.epd

- a number of random games are played, at random evaluation calls the positions are collected
- non-quiet and positions without legal moves are removed
- from the remaining games will be played one game each with Nalwald at ~80ms per move
- the result of that game will be the target value of the position

###### quietSmallNalwaldCCRL4040.epd

- a number of positions from CCRL4040 games are randomly selected (without early opening positions)
- non-quiet and positions without legal moves are removed
- from the remaining games will be played one game each with Nalwald at ~80ms per move
- the result of that game will be the target value of the position

###### quietSetCombinedCCRL4040.epd

- the target value of the positions of `quietSmallNalwaldCCRL4040.epd` will be averaged over the results of the respective CCRL4040 games (of players with Elo 2700 and higher) and the games that Nalwald played

###### CCRL404FRC.epd

- just some randomly selected positions from CCRL games of engines over 2900 Elo
- no preprocessing

###### quietSmallLichessGamesSet.epd

- downloaded some games from lichess
- removed all games that ended with time forfeit
- chose randomly positions such that we get to ~6 million positions
- (I forgot to remove non-quiet position, so yeah ... this file is misnamed)
- labeled by the result the game on lichess