CREATE TABLE users (
	name TEXT PRIMARY KEY
);

CREATE TABLE channels (
	name TEXT,
	network TEXT,
	PRIMARY KEY (name, network)
);

CREATE TABLE stats (
	user INT REFERENCES users (name) ON DELETE CASCADE,
	channel INT REFERENCES channels (name) ON DELETE CASCADE,
	network INT REFERENCES channels (network) ON DELETE CASCADE,
	-- [time, time + timespan] time period
	time INT,
	timespan INT,

	letters INT,
	words INT,
	actions INT,
	smileys INT,
	kicks INT,
	modes INT,
	topics INT,
	seconds INT,

	PRIMARY KEY (user, channel, network, time, timespan)
);

CREATE TABLE words (
	user INT REFERENCES users (name) ON DELETE CASCADE,
	channel INT REFERENCES channels (name) ON DELETE CASCADE,
	network INT REFERENCES channels (network) ON DELETE CASCADE,
	word TEXT,

	hits INT,
	last INT, -- timestamp

	PRIMARY KEY (user, channel, network, word)
);

-- stats shakedown:
-- each segment adds at a timespan boundary (each hour-segment time is divisible by 3600, etc.)
-- last 24 hours are kept in 1-minute segments
-- if there exists a 1m segment from last midnight, merge all 1m segments from prev. day to a 1-day segment
-- if there exists a 1d segment from lastmonth 1st, merge all 1d segments from prev. month to a 1-month segment
-- if there exists a 1y segment from lastyear Jan 1, merge all 1y segments from prev. year to a 1-year segment
