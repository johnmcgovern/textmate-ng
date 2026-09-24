Title: Contributions
CSS: css/contributions.css

# Contributions

TextMate-NG is built on [TextMate 2][tm2], written by Allan Odgaard, with
contributions from everyone below. The full history is in the
[repository on GitHub][commits].

<div>
<%# (No blank lines inside this div: gen_html runs Markdown *before* ERB, and a blank
    line would end the HTML block and hand the rest to Markdown to mangle.)
    Names only, from this checkout's own git history, most commits first.
    This page used to show every commit since 2012, each with an avatar
    loaded from gravatar.com — over a thousand requests to a third party
    every time the tab was opened, telling it who was running the editor,
    and publishing an MD5 of each contributor's email address. Building it
    also asked the GitHub API about every author, so an About page needed
    the network and a rate limit to compile. It was 2.4 MB, and grew with
    every commit.
    No email addresses, no images, no network: the same checkout always
    produces the same page. Without git history (a source archive, say) the
    page says so rather than failing the build. %>
<%
  require 'cgi'
  root  = ENV['SRCROOT'] || Dir.pwd
  names = `git -C "#{root}" shortlog -s -n --no-merges HEAD 2>/dev/null`.lines.map { |line| line.split("\t", 2)[1].to_s.strip }.reject(&:empty?)
-%>
<% if names.empty? -%>
<p class="contributors-missing">This copy was built without its git history, so the list of contributors is not available here.</p>
<% else -%>
<ol class="contributors">
<% names.each do |name| -%>
  <li><%= CGI.escapeHTML(name) %></li>
<% end -%>
</ol>
<% end -%>
</div>

[tm2]: https://github.com/textmate/textmate
[commits]: https://github.com/johnmcgovern/textmate-ng/commits/master
