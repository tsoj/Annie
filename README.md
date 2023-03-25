# Annie

I want to introduce you to Annie, a chess bot for Lichess. She's excited about exploring the more intricate sides of chess. Her favorite openings are the cloud variations and she is a very enthusiastic fan of en passant in every imaginable form.

Annie's handcrafted, large-table powered evaluation was trained on no fewer than six million, four hundred and thirty-four positions from games played on Lichess. And not just the games of grandmasters, but the games of noobs and sub-800 Elo players, too. On top of that, she also has an anarchic sub-module in her tree search. So be prepared for some unconventional moves (and comments).

You can play Annie [here](https://lichess.org/@/Annie_Archy) (bullet, blitz, or rapid, always with increment and unrated).

Depending on how well you've played recently, a level from **A1** to **C3** will be suggested. If you only understand the most established strategies that grandmasters tend to go for, you better play against Annie at level **C1**, **C2**, or even **C3**. But if you have experience battling the chaos of playing against 800 Elo prodigies and if you can keep your composure when facing an opponent with a question mark next to their rating, you should play against level **A3**, **A2**, or if you're really mad, against level **A1**. All you players who are ordinary that it hurts, give the **B** levels a try.

Annie is based on the chess engine [Nalwald](https://gitlab.com/tsoj/Nalwald).

### Compiling and running

First you need [Nim](https://nim-lang.org/), [nimpy](https://github.com/yglukhov/nimpy), [Python](https://www.python.org/), and [Requests](https://pypi.org/project/requests/).

Copy `config.default.json` to `config.json` and replace the place-holder for `"lichessToken"` with your lichess bot account token. You can also edit the other available config parameters.

Now run `./runLichessBot.sh` and you can start playing the bot on lichess!

(Some of the code also has an anarchy feeling to it, but that's definitely intended ...)

### License

Copyright © Jost Triller
