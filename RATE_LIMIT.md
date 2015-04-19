
# Rate Limiting

## The Short Version

* Each channel has its own settings for rate limiting
* You need to be +o and in the channel in order to view or change these settings
* You can view them with:
  ```!set rate_limit::``` from inside the channel
* You can set them with:
  ```!set rate_limit::thing = <bucket> + <rate>``` from inside the channel

## Buckets and Rates

Where "thing" is a thing you want to rate limit, "bucket" is a number of times the thing can be used in a burst and "rate" is how quickly (in uses per second) the bucket refills. The "thing" cannot be used unless the bucket contains a number greater than or equal to 1, and any use of the thing subtracts 1 from the bucket.

So, "five uses, but they refresh at a rate of one per minute" would be:

  ```!set rate_limit::thing = 5 + 0.016666666666666666```

and "1 use, every 30 seconds" would be:

  ```!set rate_limit::thing = 1 + 0.03333333333333333```

## Things

Everything you can ask the bot to do ties in to a feature, which is a collective name for a particular set of commands and options. Features can be enabled or disabled on a per-user, per-channel, per-network or global level. 

You can also rate limit the bot's features. The following will apply a single rate limit to every dice or probability command (!roll, !qroll, !toss, !prob, !average, etc):

  ```!set rate_limit::dice = 1 + 0.03333333333333333```

You can also set rate limits on individual commands. This can be done by setting a rate limit on "!command/command-name". For instance, to apply a limit to the "!prob" command only, the following will suffice:

  ```!set rate_limit::!command/prob = 1 + 0.016666666666666666```

### Specific overrides general

If you have both a rate limit on a command level and on the feature level, the command level rate limit will be applied (and using that particular command will not count as a use of the feature).

### Adding a message

You can set a message to be included in the rate limit command:

  ```!set channel::options::rate_limit_message = "Bugger off."```

This will be included in all rate limit messages
