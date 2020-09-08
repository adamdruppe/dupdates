module dupdates.main; // aka DWIDDER

import arsd.cgi;
import arsd.dom;
import arsd.postgres;
import arsd.webtemplate;

import std.conv;

/+
	FIXME: XSRF

	listing of posts by user not done
+/

bool isIdentifierChar(char c) {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '_';
}

struct ParsedPost {
	this(string content) {
		original = content;

		rendered = Element.make("div");

		auto current = rendered.addChild("p");

		size_t last;
		for(size_t idx = 0; idx < content.length; idx++) {
			auto ch = content[idx];

			if(ch == '#') {
				auto begin = idx;
				idx++;
				while(idx < content.length && isIdentifierChar(content[idx]))
					idx++;

				if(begin + 1 < idx && !(content[begin + 1] >= '0' && content[begin + 1] <= '9')) {
					current.appendText(content[last .. begin]);
					current.addChild("a", content[begin .. idx], "/search?tag=" ~ Uri.encode(content[begin + 1 .. idx]));

					hashtags ~= content[begin + 1 .. idx].toLower;

					last = idx;
					idx--;
				}

			} else if(ch == '`') {
				if(idx + 1 < content.length) {
					import std.string;
					if(idx + 6 < content.length && content[idx .. idx + 3] == "```") {
						current.appendText(content[last .. idx]);
						while(idx < content.length && content[idx] != '\n')
							idx++;
						auto begin = idx;

						while(idx + 3 < content.length && content[idx .. idx + 3] != "```")
							idx++;
						rendered.addChild("pre", content[begin .. idx].stripRight);
						current = rendered.addChild("p");

						while(idx < content.length && content[idx] != '\n')
							idx++;
						while(idx < content.length && (content[idx] == '\n' || content[idx] == '\r'))
							idx++;

						last = idx;
						idx--;

					} else {
						auto begin = idx;

						idx++;
						while(idx < content.length && content[idx] != '`')
							idx++;

						if(idx < content.length)
							idx++; // include the `

						current.appendText(content[last .. begin]);
						current.addChild("tt", content[begin .. idx]);
						last = idx;
					}
				}
			} else if(ch == 'h') {
				if((idx + 7 < content.length && content[idx .. idx + 7] == "http://") ||
					(idx + 8 < content.length && content[idx .. idx + 8] == "https://"))
				{
					auto start = idx;

					while(idx < content.length && content[idx] != ' ' && content[idx] != '\n' && content[idx] != '>' && content[idx] != ']' && content[idx] != ')')
						idx++;

					current.appendText(content[last .. start]);
					current.addChild("a", content[start .. idx], content[start .. idx]);
					last = idx;
					idx--;
				}

			} else if(ch == '\n') {
				if(idx + 2 < content.length && (content[idx + 1] == '\n' || (content[idx + 1] == '\r' && content[idx + 2] == '\n'))) {
					while(idx < content.length && content[idx] == '\n' || content[idx] == '\r')
						idx++;

					current.appendText(content[last .. idx]);
					last = idx;
					current = rendered.addChild("p");
					idx--;
				} else {
					current.appendText(content[last .. idx]);
					last = idx;
					current.addChild("br");
				}
			}
		}

		current.appendText(content[last .. $]);
	}

	string original;
	Element rendered;
	string[] hashtags;
}

struct LoginData {
	int userId;
}

int checkUserAccount(Cgi cgi) {
	auto ld = cgi.getSessionObject!LoginData;
	if(ld.userId)
		return ld.userId;

	auto username = cgi.request("username");
	auto password = cgi.request("password");
	auto email = cgi.request("email");
	auto dlang = cgi.request("dlang");

	if(dlang.toLower != "d programming language")
		throw new Exception("Sorry, wrong captcha.");

	import arsd.argon2;

	foreach(row; db.query("SELECT id, auth FROM users WHERE lower(name) = lower(?)", username)) {
		if(!verify(row[1], password))
			throw new Exception("Sorry, wrong password for existing username. Try a new username or fix your password.");
		return (ld.userId = row[0].to!int);
	}

	foreach(row; db.query("INSERT INTO users (name, email, auth) VALUES (?, ?, ?) RETURNING id", username, email, encode(password, LowSecurity)))
		return (ld.userId = row[0].to!int);


	assert(0);
}

class DUpdate : WebObject {
	this() { }

	@UrlName("")
	@Template("home.html")
	Paginated!Post recentPosts(string cursor = null) {
		string startTime = "2300-12-31";
		string startId = "999999999";
		if(cursor.length) {
			import std.string;
			auto idx = cursor.indexOf("!");
			if(idx == -1)
				throw new Exception("invalid cursor");
			startTime = cursor[0 .. idx];
			startId = cursor[idx + 1 .. $];
		}
		Post[] ret;
		foreach(row; db.query("
			SELECT
				p.id, p.content, p.date_posted, users.name, count(c.id) AS comments
			FROM
				posts AS p
			INNER JOIN
				users ON p.user_id = users.id
			LEFT OUTER JOIN
				posts AS c ON c.parent_id = p.id
			WHERE
				p.parent_id IS NULL
				AND
				p.date_posted < ?
				AND
				p.id < ?
			GROUP BY
				p.id, users.id
			ORDER BY
				p.date_posted DESC,
				p.id DESC
			LIMIT
				30
		",
			startTime, startId))
		{
			Post p;

			p.id = to!int(row["id"]);
			p.content = ParsedPost(row["content"]);
			p.date = row["date_posted"];
			p.author = row["name"];
			p.commentCount = row["comments"].to!int;

			p.link = "/posts/" ~ row["id"];

			ret ~= p;
		}

		string next;
		if(ret.length == 30) {
			next = "/?cursor=" ~ Uri.encode(ret[$-1].date ~ "!" ~ ret[$-1].id.to!string);
		}

		return typeof(return)(ret, next);
	}

	@(Cgi.RequestMethod.POST)
	@UrlName("posts")
	Redirection post(Cgi cgi, string content) {
		auto uid = checkUserAccount(cgi);
		if(content.length == 0)
			return Redirection("/");
		auto post = ParsedPost(content);
		foreach(row; db.query("INSERT INTO posts (content, date_posted, user_id) VALUES (?, now(), ?) RETURNING id",
			post.original, uid))
		{
			saveHashtags(post.hashtags, row[0]);
			return Redirection("/posts/" ~ row[0]);
		}

		throw new Exception("creation failed");
	}

	@(Cgi.RequestMethod.POST)
	@UrlName("comments")
	Redirection comment(Cgi cgi, string content, int parentId) {
		auto uid = checkUserAccount(cgi);
		if(content.length == 0)
			return Redirection("/");
		auto post = ParsedPost(content);
		foreach(row; db.query("INSERT INTO posts (content, date_posted, user_id, parent_id) VALUES (?, now(), ?, ?) RETURNING id",
			post.original, uid, parentId))
		{
			saveHashtags(post.hashtags, row[0]);
			return Redirection("/posts/" ~ to!string(parentId) ~ "#comment-" ~ row[0]);
		}

		throw new Exception("creation failed");
	}

	@Template("recent-comments.html")
	Paginated!Post search(string tag, string cursor = null) {
		string startTime = "2300-12-31";
		string startId = "999999999";
		if(cursor.length) {
			import std.string;
			auto idx = cursor.indexOf("!");
			if(idx == -1)
				throw new Exception("invalid cursor");
			startTime = cursor[0 .. idx];
			startId = cursor[idx + 1 .. $];
		}
		Post[] ret;
		foreach(row; db.query("
			SELECT
				p.id, p.content, p.date_posted, users.name, p.parent_id, c.content AS parent_snippet
			FROM
				posts AS p
			INNER JOIN
				users ON p.user_id = users.id
			INNER JOIN
				post_hashtags ON post_id = p.id
			INNER JOIN
				hashtags ON hashtags.id = hashtag_id
			LEFT OUTER JOIN
				posts AS c ON p.parent_id = c.id
			WHERE
				hashtags.content = ?
				AND
				p.date_posted < ?
				AND
				p.id < ?
			ORDER BY
				p.date_posted DESC,
				p.id DESC
			LIMIT
				30
		",
			tag.toLower, startTime, startId))
		{
			Post p;

			p.id = to!int(row["id"]);
			p.content = ParsedPost(row["content"]);
			p.date = row["date_posted"];
			p.author = row["name"];

			p.parentSnippet = row["parent_snippet"];

			if(row["parent_id"].length)
				p.link = "/posts/" ~ row["parent_id"] ~ "#comment-" ~ row["id"];
			else
				p.link = "/posts/" ~ row["id"];

			ret ~= p;
		}

		string next;
		if(ret.length == 30) {
			next = "/search?tag="~Uri.encode(tag)~"&cursor=" ~ Uri.encode(ret[$-1].date ~ "!" ~ ret[$-1].id.to!string);
		}

		return typeof(return)(ret, next);


	}

	@Template("recent-comments.html")
	Paginated!Post recentComments(string cursor = null) {
		string startTime = "2300-12-31";
		string startId = "999999999";
		if(cursor.length) {
			import std.string;
			auto idx = cursor.indexOf("!");
			if(idx == -1)
				throw new Exception("invalid cursor");
			startTime = cursor[0 .. idx];
			startId = cursor[idx + 1 .. $];
		}
		Post[] ret;
		foreach(row; db.query("
			SELECT
				p.id, p.content, p.date_posted, users.name, p.parent_id, c.content AS parent_snippet
			FROM
				posts AS p
			INNER JOIN
				users ON p.user_id = users.id
			LEFT OUTER JOIN
				posts AS c ON p.parent_id = c.id
			WHERE
				p.parent_id IS NOT NULL
				AND
				p.date_posted < ?
				AND
				p.id < ?
			ORDER BY
				p.date_posted DESC,
				p.id DESC
			LIMIT
				30
		",
			startTime, startId))
		{
			Post p;

			p.id = to!int(row["id"]);
			p.content = ParsedPost(row["content"]);
			p.date = row["date_posted"];
			p.author = row["name"];

			p.parentSnippet = row["parent_snippet"];

			p.link = "/posts/" ~ row["parent_id"] ~ "#comment-" ~ row["id"];

			ret ~= p;
		}

		string next;
		if(ret.length == 30) {
			next = "/recent_comments?cursor=" ~ Uri.encode(ret[$-1].date ~ "!" ~ ret[$-1].id.to!string);
		}

		return typeof(return)(ret, next);

	}
}

void saveHashtags(string[] hashtags, string pid) {
	foreach(tag; hashtags)
	foreach(row; db.query("WITH n AS (
		INSERT INTO hashtags (content) VALUES (?) ON CONFLICT (content) DO NOTHING RETURNING id
	) SELECT COALESCE( (SELECT id FROM n), (SELECT id FROM hashtags WHERE content = ?) )",
		tag, tag))
	{
		db.query("INSERT INTO post_hashtags (hashtag_id, post_id) VALUES (?, ?) ON CONFLICT (hashtag_id, post_id) DO NOTHING", row[0], pid);
	}
}

struct Post {
	int id;
	string author;
	ParsedPost content;
	string date;

	string link;

	int commentCount;

	string parentSnippet;
}

class PostController : WebObject {
	string id;
	this(string id) {
		this.id = id;
	}

	@UrlName(null)
	@Template("post.html")
	Post[] show() {
		Post[] ret;
		foreach(row; db.query("
			SELECT
				p.id, p.content, p.date_posted, users.name, p.parent_id
			FROM
				posts AS p
			INNER JOIN
				users ON p.user_id = users.id
			WHERE
				p.id = ? OR p.parent_id = ?
			ORDER BY
				p.date_posted ASC
		", id, id))
		{
			Post p;

			p.id = to!int(row["id"]);
			p.content = ParsedPost(row["content"]);
			p.date = row["date_posted"];
			p.author = row["name"];

			if(row["parent_id"].length)
				p.link = "/posts/" ~ row["parent_id"] ~ "#comment-" ~ row["id"];
			else
				p.link = "/posts/" ~ row["id"];

			ret ~= p;
		}

		return ret;
	}
}

MyPresenter presenter;
PostgreSql db;

void handler(Cgi cgi) {
	if(presenter is null)
		presenter = new MyPresenter();
	if(db is null)
		db = new PostgreSql("dbname=dupdate");

	if(cgi.dispatcher!(
		"/assets/".serveStaticFileDirectory,
		"/posts/".serveApi!PostController,
		"/".serveApi!DUpdate
	)(presenter)) return;

	presenter.renderBasicError(cgi, 404);
}

class MyPresenter : WebPresenterWithTemplateSupport!MyPresenter {
	override void addContext(Cgi cgi, var ctx) {
		auto ld = cgi.getSessionObject!LoginData;
		ctx.user = ld.userId;
	}
}

mixin GenericMain!handler;
