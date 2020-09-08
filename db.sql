CREATE TABLE users (
	id SERIAL,
	name TEXT NOT NULL,
	email TEXT NULL,
	auth TEXT,
	PRIMARY KEY(id)
);
CREATE UNIQUE INDEX users_by_name ON users (lower(name));
CREATE TABLE posts (
	id SERIAL,
	user_id INTEGER NOT NULL,
	parent_id INTEGER NULL,
	content TEXT NOT NULL,
	date_posted TIMESTAMPTZ NOT NULL,

	FOREIGN KEY(parent_id) REFERENCES posts(id) ON UPDATE CASCADE ON DELETE CASCADE,
	FOREIGN KEY(user_id) REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE,
	PRIMARY KEY(id)
);
CREATE INDEX posts_by_date ON posts(date_posted);

CREATE TABLE hashtags (
	id SERIAL,
	content TEXT NOT NULL,
	PRIMARY KEY(id)
);
CREATE UNIQUE INDEX hashtags_by_content ON hashtags(content);

CREATE TABLE post_hashtags (
	hashtag_id INTEGER NOT NULL,
	post_id INTEGER NOT NULL,
	PRIMARY KEY(hashtag_id, post_id)
);
