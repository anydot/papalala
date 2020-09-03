CREATE TABLE link(channel, url);
CREATE UNIQUE INDEX link_idx on link(channel, url);
