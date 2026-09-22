export type LaneWisdomCategory = 'FACT' | 'BOWLER' | 'CENTER'

export type LaneWisdomEntry = {
  category: LaneWisdomCategory
  text: string
}

export const LANE_WISDOM_ROTATION_MS = 300_000

const entries = (category: LaneWisdomCategory, texts: string[]): LaneWisdomEntry[] => texts.map(text => ({ category, text }))

export const LANE_WISDOM: LaneWisdomEntry[] = [
  ...entries('FACT', [
    'A perfect game takes 12 consecutive strikes.',
    'The head pin is 60 feet from the foul line.',
    'A regulation lane is about 41½ inches wide.',
    'A regulation approach is at least 15 feet long.',
    'Three strikes in a row is a turkey.',
    'Two strikes in a row is a double.',
    'A Brooklyn hits the opposite pocket.',
    'The pocket is 1–3 for right-handers and 1–2 for left-handers.',
    'The Big Four is the 4–6–7–10 split.',
    'The 2–7 and 3–10 are called baby splits.',
    'The Greek Church is the 4–6–7–8–10 or 4–6–7–9–10.',
    "Deadwood is a pin that can't be swept into the back.",
    'In bowling lingo, a “180” can mean the pin sweep is stuck in the back.',
    'Scratch score means the score before handicap is applied.',
    'The arrows are aiming targets, not decorations.',
    'The dots on the approach can help line up your feet.',
    "A ball that enters the gutter and comes back out still can't score those pins.",
    'Bowling on the wrong lane can mean throwing the shot again.',
    "Crossing the foul line without releasing the ball isn't automatically a foul.",
    'A regulation bowling pin is 15 inches tall.',
    'A regulation pin weighs between 3 lb. 6 oz. and 3 lb. 10 oz.',
    'There are 39 boards across a regulation lane.',
    'Lane oil changes how and where a bowling ball hooks.',
    'As lanes break down, ball reaction can change significantly.',
    'Bowling etiquette says the first bowler on the approach goes first.',
  ]),
  ...entries('BOWLER', [
    'The 10 pin has never apologized.',
    'Neither has the 7 pin.',
    "The pins aren't moving. Adjust accordingly.",
    'Somewhere, someone is blaming the lane.',
    'House balls have seen things.',
    "The ball return always knows when you're in a hurry.",
    "The foul line isn't a suggestion.",
    'Every bowler has a spare system. Some systems are mostly hope.',
    'Never celebrate until the 10 pin actually falls.',
    'Every ugly strike deserves the same X.',
    'The scoreboard doesn\'t have a column for “looked good.”',
    "Carry is skill when it's yours. Luck when it's theirs.",
    "There's always one pin that didn't get the memo.",
    "The pins can't hear your explanation.",
    'The lane has no memory. Bowlers absolutely do.',
    'A Brooklyn counts exactly the same on the scoreboard.',
    'The pocket forgives a lot. Corner pins do not.',
    'Nothing improves confidence like a completely accidental strike.',
    "The easiest spare is the one you didn't leave.",
    '“One more game” has caused a lot of late nights.',
    'A split is just a spare with unreasonable expectations.',
    "You weren't robbed. But that pin probably should've fallen.",
    'Good bowlers adjust. Great bowlers complain first, then adjust.',
    'If you leave the 10 pin, staring at it is mandatory.',
    'If you leave the 7 pin, left-handers understand.',
    'Bowling math gets easier after three strikes.',
    'One good shot can erase a lot of bad decisions.',
    'A gutter ball still counts as exercise.',
    'Bowling shoes protect the approach. Fashion was secondary.',
    'The pins have done nothing wrong. Hit them anyway.',
    'The approach remembers every spilled drink.',
    'Nobody has ever missed because someone yelled “don\'t miss.”',
    'Every bowler knows exactly what they did wrong immediately after doing it.',
    "It's always obvious where you should've moved after the shot.",
    'The tenth frame has ruined many relaxing evenings.',
  ]),
  ...entries('CENTER', [
    'Every lane has a personality. Lane 8 has several.',
    'If the machine makes a new noise, someone will hear it.',
    'The ball return works faster when nobody is waiting for it.',
    'A stuck pinsetter can sense a full house.',
    'Machines only misbehave when someone is watching.',
    'The lane you need is always the one being worked on.',
    'Nothing attracts attention like a pinsetter stopping mid-cycle.',
    'The quickest way to find a problem is to get busy.',
    'Every bowling center has one machine with “personality.”',
    "If everything is running perfectly, don't say it out loud.",
    'Bowling centers run on electricity, oil, and somebody knowing what that noise means.',
    "The quietest machine is the one you're currently worried about.",
    'If it fixes itself, it will be back.',
    'There is no such thing as a convenient time for a lane call.',
    'Lane 8 knows what it did.',
  ]),
]

const categoryWeights: readonly [LaneWisdomCategory, number][] = [['FACT', .25], ['BOWLER', .5], ['CENTER', .25]]

export function selectLaneWisdom(previous?: LaneWisdomEntry, random = Math.random): LaneWisdomEntry {
  const roll = random()
  let remaining = roll
  let category: LaneWisdomCategory = 'CENTER'
  for (const [candidate, weight] of categoryWeights) {
    remaining -= weight
    if (remaining < 0) { category = candidate; break }
  }
  const eligible = LANE_WISDOM.filter(entry => entry.category === category && entry.text !== previous?.text)
  const pool = eligible.length ? eligible : LANE_WISDOM.filter(entry => entry.text !== previous?.text)
  return pool[Math.min(pool.length - 1, Math.floor(random() * pool.length))]
}
