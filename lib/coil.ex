defmodule Coil do
  use Application.Behaviour

  def start(_type, _args) do
    dispatch = :cowboy_router.compile([
                 {:_, [
                        {"/", Coil.TopPageHandler, []},
                        {"/assets/[:...]", :cowboy_static, { :dir, "assets" } },
                        {"/feed", Coil.RSSHandler, []},
                        {"/archives", Coil.ArchivesHandler, []},
                        {"/articles/[:...]", Coil.ArticleHandler, []},
                        {"/[:...]", Coil.PageHandler, []}
                      ]}
               ])

    port = binary_to_integer(System.get_env("PORT") || "8080")

    {:ok, _} = :cowboy.start_http(:http, 100,
                                  [port: port],
                                  [env: [dispatch: dispatch]])

    Coil.Supervisor.start_link
  end

  def article_regex do
    ~r/(?<path>(?<date>\w{4}-\w\w?-\w\w?)-(?<title>[\w-]+))\.md$/g
  end

  def headers, do: [ {"Content-Type", "text/html; charset=UTF-8" } ]

  def articles do
    File.ls!("articles") |> Enum.filter(fn(a) -> article_regex |> Regex.match?(a) end)
    |> Enum.sort(&(&2 < &1)) |> Enum.map(&article/1)
  end

  def article(filename) do
    article = :gen_server.call(:cache_server, "articles/#{filename}")

    if article == nil, do: article = load_article("articles/#{filename}")

    article
  end

  def page(filename) do
    page = :gen_server.call(:cache_server, "pages/#{filename}")

    if page == nil, do: page = load_page("pages/#{filename}")

    page
  end

  def template(filename) do
    template = :gen_server.call(:cache_server, "templates/#{filename}")

    if template == nil, do: template = load_template("templates/#{filename}")

    template
  end

  def template(filename, keys) do
    {result, _} = Code.eval_quoted(template(filename), keys)

    result
  end

  def config do
    config = :gen_server.call(:cache_server, "config.yml")

    if config == nil do
      config = :yamerl_constr.file("config.yml") |> List.flatten
      :gen_server.cast(:cache_server, ["config.yml", config])
    end

    config
  end

  def config(key) do
    config[String.to_char_list!(key)] |> String.from_char_list!
  end

  defp load_template(filename) do
    :gen_server.cast(:cache_server, [filename, EEx.compile_file(filename)])
    :gen_server.call(:cache_server, filename)
  rescue File.Error -> nil
  end

  defp load_page(filename) do
    content = File.read!(filename) |> Markdown.to_html

    meta = ~r/(?<title>[\w-]+)\.md$/g |> Regex.named_captures filename

    :gen_server.cast(:cache_server, [filename, [
      content: content,
      title: meta[:title] |> String.capitalize |> String.replace("-", " "),
      md5: :crypto.hash(:md5, content) ]
    ])

    :gen_server.call(:cache_server, filename)
  rescue File.Error -> nil
  end

  defp load_article(filename) do
    content = File.read!(filename) |> Markdown.to_html
    summary = (~r/(?<summary><p>.*?<\/p>)/gs |> Regex.named_captures content)[:summary]
    meta = article_regex |> Regex.named_captures filename

    :gen_server.cast(:cache_server, [filename, [
      content: content,
      summary: summary,
      md5: :crypto.hash(:md5, content),
      title: meta[:title] |> String.capitalize |> String.replace("-", " "),
      path: "articles/#{meta[:path]}",
      date: meta[:date] ]
    ])

    :gen_server.call(:cache_server, filename)
  rescue File.Error -> nil
  end
end
