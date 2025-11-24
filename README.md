# FancyMiner
a fancy mining program for the CC-Tweaked mod in Minecraft

## what is FancyMiner?

fancy miner is a collection of scripts to mine a quarry (or stairs down the quarry)
and get status feedback either to a pocket computer running recieve.lua,
or advanced computer (best use with a 2x2 advanced monitor on scale 0.5) running recieve.lua

### pre setup

recievers need
- flex.lua
- recieve.lua

the turtle miner needs
- dig.lua
- flex.lua
- quarry.lua
- stairs.lua

quarry.lua is for excavating
stairs.lua for getting down safely (places stairs down the quarry)

also for the transmitting part, the turtle as well as the reciever need a ender_modem for best efficiency
(I did not test the use with wireless modem, as it is not working over dimensions, and who doesn't want to be always able to track the progress of your dear turtle?)
### usage
to use the script best run flex.lua once and aftewards dig.lua once.
flex will create a flex_options.cfg which has the modem_channel for monitoring
dig will create some lists to use

## setup instructions

copy the follwing into your cctweaked computer:
```txt
wget run https://raw.githubusercontent.com/Sedrowow/FancyMiner-CCTweaked/aaaa/
```

CREDIT GOES TO [Flexico](https://github.com/Flexico) that made the original  [Digsoft: A Fancy Resumable Quarry Program](https://forums.computercraft.cc/index.php?topic=316.0)]
i improved upon his script, as i thought, its a good start
i thank him whereas he made the most work. if he wants me to take these improved scripts down, i will not hestitate to do so, as i didnt asked for hsi consent yet.
