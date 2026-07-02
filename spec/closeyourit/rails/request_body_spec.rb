# frozen_string_literal: true

require "stringio"

RSpec.describe CloseYourIt::Rails::RequestBody do
  before do
    CloseYourIt.init do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
      c.async_threads = 0
    end
  end

  def body_env(body, content_type:)
    {
      "REQUEST_METHOD" => "POST",
      "CONTENT_TYPE" => content_type,
      "CONTENT_LENGTH" => body.bytesize.to_s,
      "rack.input" => StringIO.new(body)
    }
  end

  it "estrae i params di un body form urlencoded, scrubbati" do
    env = body_env("name=Anna&password=hunter2", content_type: "application/x-www-form-urlencoded")

    expect(described_class.extract(env)).to eq("name" => "Anna", "password" => "[FILTERED]")
  end

  it "estrae e scruba un body JSON" do
    env = body_env('{"email":"a@b.it","api_key":"k-1"}', content_type: "application/json")

    expect(described_class.extract(env)).to eq("email" => "a@b.it", "api_key" => "[FILTERED]")
  end

  it "preferisce i params già parsati da Rails senza rileggere il body" do
    env = {
      "REQUEST_METHOD" => "POST",
      "action_dispatch.request.request_parameters" => { "q" => "ok", "password" => "x" }
    }

    expect(described_class.extract(env)).to eq("q" => "ok", "password" => "[FILTERED]")
  end

  it "sostituisce gli upload con un placeholder [FILE]" do
    upload = double("UploadedFile", original_filename: "avatar.png")
    env = {
      "REQUEST_METHOD" => "POST",
      "action_dispatch.request.request_parameters" => { "avatar" => upload, "title" => "ciao" }
    }

    data = described_class.extract(env)
    expect(data["avatar"]).to eq("[FILE: avatar.png]")
    expect(data["title"]).to eq("ciao")
  end

  it "sostituisce gli oggetti non serializzabili con un placeholder di classe" do
    env = {
      "REQUEST_METHOD" => "POST",
      "action_dispatch.request.request_parameters" => { "weird" => Object.new }
    }

    expect(described_class.extract(env)).to eq("weird" => "[OBJECT: Object]")
  end

  it "tronca i valori stringa oltre 1024 caratteri" do
    env = body_env({ note: "x" * 5000 }.to_json.to_s, content_type: "application/json")

    expect(described_class.extract(env)["note"].size).to be <= 1025
  end

  it "rilegge il body lasciandolo disponibile all'app (rewind)" do
    raw = '{"a":1}'
    env = body_env(raw, content_type: "application/json")

    described_class.extract(env)
    expect(env["rack.input"].read).to eq(raw)
  end

  it "ritorna nil oltre il cap di dimensione" do
    env = body_env("a=1", content_type: "application/json")
    env["CONTENT_LENGTH"] = (described_class::MAX_BODY_BYTES + 1).to_s

    expect(described_class.extract(env)).to be_nil
  end

  it "ritorna nil per content-type non supportato" do
    expect(described_class.extract(body_env("<xml/>", content_type: "text/xml"))).to be_nil
  end

  it "non solleva su JSON malformato (ritorna nil)" do
    expect(described_class.extract(body_env("{nope", content_type: "application/json"))).to be_nil
  end

  it "ritorna nil senza body né params" do
    expect(described_class.extract("REQUEST_METHOD" => "GET")).to be_nil
  end
end
