# Video loop prompts (round 8, MiniMax H3)

Every loop: `minimax_h3`, resolution 2K, 8 s, the scene picture from `gen2/` as both `start_image` and
`end_image`. Hero pictures (3:2) were stretched to 16:9 (4153 x 2336) before upload; the others were sent as they
are (16:9, or 21:9 for the footer and the inner-page banner). Job IDs are in `credits.md`. Every prompt starts
with the same opening and ends with the same closing:

> Animate this hand-drawn cartoon illustration of {place} as a calm, seamless looping shot. The camera is
> completely locked off on a tripod: no pan, no zoom, no dolly, no shake; the frame never moves. Keep the exact
> flat line-art style, colours and black outlines. {still}. {motion}. {people}. Nobody walks in or out, no new
> people or objects appear. The last frame is identical to the first frame.

| Scene | {place} | {still} (stay perfectly rigid and still) | {motion} | {people} |
|---|---|---|---|---|
| Hero, Light | (none: "this hand-drawn cartoon illustration") | The buildings, skyline, lamp posts, red bench, stone block, paved path and round planter | A gentle summer breeze: tree leaves rustle and branches sway softly, tulips and daisies nod gently on their stems, the white clouds drift slowly, the two birds flap and glide, the little airplane moves slowly along its trail, the butterflies flutter | The five people stay in place in their poses and remain exactly the same people, just alive: they blink, breathe, smile and make small natural movements; the waving girl waves her hand a little; the skateboarder hovers mid-air above his board in the same pose, his shirt fluttering |
| Hero, Dusk | a park at dusk | as Light | A gentle evening breeze: as Light, with pink clouds and the airplane's light blinking. The two street lamps glow warmly with a soft flicker, the city windows glimmer and the stars twinkle | as Light |
| Features, Light | a sunny park meadow | The distant city skyline, the winding path and the rocks | A gentle summer breeze: tree leaves rustle and branches sway softly, the grass, reeds, bushes, tulips and daisies sway gently, the pond's surface ripples softly, the white clouds drift slowly, the two birds flap and glide | The four friends and their little dog stay in place in their poses and look exactly the same, just alive: they blink, breathe, smile and make small friendly movements; the young woman walking the dog and the young man jogging stay mid-step on the spot, only their hair and jackets moving a little; the young man sitting on the rock looks at his phone; the dog pants and wags its tail |
| Features, Dusk | a meadow at dusk | as Light | as Light, with pink clouds, fireflies glowing and drifting over the grass, stars twinkling and city windows glimmering | as Light (worded "the walking girl and the jogging boy stay mid-stride on the spot"; the Light run with that wording was flagged by mistake) |
| Pricing, Light | a sunny rooftop terrace | The buildings, skyline, glass railing, wooden deck, pergola, table, chairs, glasses, lounger and planters | A gentle summer breeze: the olive tree leaves rustle and branches sway softly, the string lights sway gently on their wire, the lavender, roses and red geraniums nod softly, the white clouds drift slowly, the red hot-air balloon floats gently, the two birds flap and glide | The four people stay in place in their poses and remain exactly the same people, just alive: they blink, breathe, smile and make small natural movements; the boy with raised fists pumps them a little; the boy in headphones claps softly |
| Pricing, Dusk | a rooftop terrace at dusk | as Light | as Light, with the string lights' warm bulbs glowing and twinkling, pink clouds, the red lantern balloon, city windows glimmering and stars twinkling | as Light |
| Footer, Light | a picnic on a grassy hill | The distant skyline, the picnic blanket and the hill | A gentle summer breeze: tree leaves rustle and branches sway softly, the grass, bushes, tulips and daisies sway gently, the red kite flutters high in the sky with its tail ribbons waving, the white clouds drift slowly, the two birds flap and glide | The five friends and the dog stay in place in their poses and remain exactly the same, just alive: they wave their hands gently, blink, breathe and smile; the dog pants and wags its tail |
| Footer, Dusk | a picnic on a grassy hill at dusk | as Light | as Light, with pink clouds, the lantern on the blanket flickering warmly, fireflies, stars and city windows | as Light |
| Inner pages, Light | a sunny city park | The buildings, skyline, lamp post, low stone wall, paved path and the bicycle | A gentle summer breeze: tree leaves rustle and branches sway softly, the bushes, tulips and daisies sway gently, the white clouds drift slowly, the two birds flap and glide, the little airplane moves slowly along its trail | The two people stay in place and remain exactly the same people, just alive: the girl sitting on the wall blinks, breathes, smiles and glances at her phone; the boy on the bicycle balances in place without riding off and waves his hand gently |
| Inner pages, Dusk | a city park at dusk | as Light | as Light, with pink clouds and the airplane's light blinking; the street lamp and the bicycle headlight glow warmly with a soft flicker, the city windows glimmer and the stars twinkle | as Light |

## Round 8b (10 s, first frame only)

Three clips were made again so their motion stays even for the whole clip (`minimax_h3`, 2K, 10 s, the scene
picture as `start_image` only). The opening is the same with "as a calm, continuous shot"; the clouds are listed
with the things that stay rigid (the script lays the still's clouds back in); "steady ... that never stops" and
"continuously" are added to the breeze; the people move "with small, steady movements all the way through"; and
the last sentence is "Even, continuous motion from the first second to the last, with no pause and no slowing
down." instead of the last-frame sentence.

- Pricing, Light: as before, and "the boy with raised fists keeps his arms up and sways a little".
- Footer, Dusk: as before, and the friends "wave their hands gently and keep waving".
- Inner pages, Light: as before, and the boy on the bicycle "waves his hand slowly and evenly the whole time".

## Round 10 (Seedance 2.5, 480p, 5 s, first and last frame, `aspect_ratio: auto`)

Wind first, then what stays still ("everything frozen" first takes the wind away):

> Start exactly on the first frame image and end exactly on the same image; do not redraw, reframe, crop or zoom it.
> Hand-drawn 2D animation of {place} on a breezy {summer day | evening at dusk}. Locked-off tripod camera.
>
> A steady {summer | evening} breeze blows through the whole {place} without ever stopping, just as strong in the last
> second as in the first: the tree crowns at both sides sway softly from side to side, a short way, several times, their
> leaf clusters rustling in place; the smaller trees, hedges and bushes in the distance sway and rustle just as clearly;
> every tulip and daisy in every bed leans and springs back on its bending stem again and again; the grass waves;
> {leaf shadows, pond, reeds, lavender, fireflies, butterflies}; the two birds flap and glide. Natural, continuous motion
> from the first frame to the last.
>
> The {n} people are the only still thing, a frozen photograph inside the moving {place}: faces, eyes, hair, hands,
> clothes, phones, bags, hats do not move at all. The clouds hang motionless. [The light does not change.] {the scene's
> objects} are rigid. Nothing new appears and nobody leaves.

Features Dusk and footer Light drew wind as white ribbons; their second prompts say "the plants never stop moving"
instead of naming a breeze, and "absolutely no wind lines, no streaks, no ribbons, no trails, no swirls, no flying
leaves, no new birds".
