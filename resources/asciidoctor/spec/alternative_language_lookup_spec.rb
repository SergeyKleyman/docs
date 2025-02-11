# frozen_string_literal: true

require 'json'
require 'tempfile'
require 'alternative_language_lookup/extension'

RSpec.describe AlternativeLanguageLookup::AlternativeLanguageLookup do
  before(:each) do
    Asciidoctor::Extensions.register do
      treeprocessor AlternativeLanguageLookup::AlternativeLanguageLookup
    end
  end

  after(:each) do
    Asciidoctor::Extensions.unregister_all
  end

  let(:spec_dir) { File.dirname(__FILE__) }
  let(:example_alternatives) do
    "#{spec_dir}/resources/alternative_language_lookup"
  end

  let(:one_snippet) do
    <<~ASCIIDOC
      [source,console]
      ----
      #{snippet_contents}
      ----
    ASCIIDOC
  end

  shared_examples "doesn't modify the output" do
    it "doesn't modify the output" do
      expect(converted).to eq(<<~DOCBOOK.strip)
        <preface>
        <title></title>
        <programlisting language="console" linenumbering="unnumbered">#{snippet_contents}</programlisting>
        </preface>
      DOCBOOK
    end
  end

  context 'when it is not configured' do
    include_context 'convert without logs'
    let(:input) { one_snippet }
    let(:snippet_contents) { 'GET /' }
    include_examples "doesn't modify the output"
  end
  context 'when it is configured to an empty string' do
    include_context 'convert without logs'
    let(:convert_attributes) { { 'alternative_language_lookups' => '' } }
    let(:input) { one_snippet }
    let(:snippet_contents) { 'GET /' }
    include_examples "doesn't modify the output"
  end
  context 'when it is configured to a missing directory' do
    include_context 'convert with logs'
    let(:config) do
      <<~CSV
        console,missing,#{example_alternatives}/missing
      CSV
    end
    let(:convert_attributes) { { 'alternative_language_lookups' => config } }
    let(:input) { one_snippet }
    let(:snippet_contents) { 'GET /' }
    include_examples "doesn't modify the output"
    it 'logs an error for the missing directory' do
      expect(logs).to eq(<<~LOG.strip)
        ERROR: invalid alternative_language_lookups, [#{example_alternatives}/missing] doesn't exist
      LOG
    end
  end
  context 'when it is configured for a different language' do
    include_context 'convert without logs'
    let(:config) do
      <<~CSV
        missing,js,#{example_alternatives}/js
      CSV
    end
    let(:convert_attributes) { { 'alternative_language_lookups' => config } }
    let(:input) { one_snippet }
    let(:snippet_contents) { 'GET /' }
    include_examples "doesn't modify the output"
  end

  context 'when it is configured' do
    let(:config) do
      <<~CSV
        console,js,#{example_alternatives}/js
        console,csharp,#{example_alternatives}/csharp
        console,java,#{example_alternatives}/java
      CSV
    end
    let(:convert_attributes) do
      {
        'alternative_language_lookups' => config,
        'alternative_language_report' =>
          Tempfile.new(%w[alternatives_report adoc]).path,
        'alternative_language_summary' =>
          Tempfile.new(%w[alternatives_summary json]).path,
      }
    end
    let(:report) do
      # read the result of the conversion to populate the dir
      converted
      # grab the contents
      File.read convert_attributes['alternative_language_report']
    end
    let(:summary) do
      # read the result of the conversion to populate the dir
      converted
      # grab the contents
      txt = File.read convert_attributes['alternative_language_summary']
      JSON.parse(txt, symbolize_names: true) unless txt.empty?
    end
    context "when there aren't any alternatives" do
      include_context 'convert without logs'
      let(:input) { one_snippet }
      let(:snippet_contents) { 'GET /no_alternatives' }
      include_examples "doesn't modify the output"
      let(:expected_log) do
        <<~LOG
          * 3fcdfa6097c68c04f3e175dcf3934af6.adoc: <stdin>: line 2
        LOG
      end
      context 'the alternatives report' do
        it 'contains the source' do
          expect(report).to include(<<~ASCIIDOC)
            === <stdin>: line 2: 3fcdfa6097c68c04f3e175dcf3934af6.adoc
            [source,console]
            ----
            GET /no_alternatives
            ----
          ASCIIDOC
        end
        it 'shows all languages as missing' do
          expect(report).to include(<<~ASCIIDOC)
            | js | csharp | java

            | &cross; | &cross; | &cross;
          ASCIIDOC
        end
      end
      context 'the summary' do
        it 'shows everything as missing' do
          expect(summary).to eq(
            console: {
              total: 1,
              alternatives: {
                js: { found: 0 },
                csharp: { found: 0 },
                java: { found: 0 },
              },
            }
          )
        end
      end
    end
    context 'when there is a single alternative' do
      include_context 'convert without logs'
      let(:input) { one_snippet }
      let(:snippet_contents) { 'GET /just_js_alternative' }
      it 'adds the alternative' do
        expect(converted).to eq(<<~DOCBOOK.strip)
          <preface>
          <title></title>
          <programlisting role="alternative" language="js" linenumbering="unnumbered">console.info('just js alternative');</programlisting>
          <programlisting role="default has-js" language="console" linenumbering="unnumbered">#{snippet_contents}</programlisting>
          </preface>
        DOCBOOK
      end
      context 'the alternatives report' do
        it 'shows only js populated' do
          expect(report).to include(<<~ASCIIDOC)
            | js | csharp | java

            | &check; | &cross; | &cross;
          ASCIIDOC
        end
      end
      context 'the summary' do
        it 'shows only js found' do
          expect(summary).to eq(
            console: {
              total: 1,
              alternatives: {
                js: { found: 1 },
                csharp: { found: 0 },
                java: { found: 0 },
              },
            }
          )
        end
      end
    end
    context 'when all alternatives exist' do
      include_context 'convert without logs'
      let(:input) { one_snippet }
      let(:snippet_contents) { 'GET /all_alternatives' }
      it 'adds the alternatives' do
        expect(converted).to eq(<<~DOCBOOK.strip)
          <preface>
          <title></title>
          <programlisting role="alternative" language="js" linenumbering="unnumbered">console.info('all alternatives');</programlisting>
          <programlisting role="alternative" language="csharp" linenumbering="unnumbered">Console.WriteLine("all alternatives");</programlisting>
          <programlisting role="alternative" language="java" linenumbering="unnumbered">System.out.println("all alternatives");</programlisting>
          <programlisting role="default has-js has-csharp has-java" language="console" linenumbering="unnumbered">#{snippet_contents}</programlisting>
          </preface>
        DOCBOOK
      end
      context 'the alternatives report' do
        it 'shows all languages populated' do
          expect(report).to include(<<~ASCIIDOC)
            | js | csharp | java

            | &check; | &check; | &check;
          ASCIIDOC
        end
      end
      context 'the summary' do
        it 'shows only js found' do
          expect(summary).to eq(
            console: {
              total: 1,
              alternatives: {
                js: { found: 1 },
                csharp: { found: 1 },
                java: { found: 1 },
              },
            }
          )
        end
      end
    end
    context 'when there are alternative results' do
      include_context 'convert without logs'
      let(:input) do
        <<~ASCIIDOC
          [source,console]
          ----
          #{snippet_contents}
          ----

          [source,console-result]
          ----
          #{result_contents}
          ----
        ASCIIDOC
      end
      let(:snippet_contents) { 'GET /just_js_alternative' }
      let(:result_contents) { '{"just_js_result": {}}' }
      it 'adds the alternative' do
        expect(converted).to eq(<<~DOCBOOK.strip)
          <preface>
          <title></title>
          <programlisting role="alternative" language="js" linenumbering="unnumbered">console.info('just js alternative');</programlisting>
          <programlisting role="default has-js" language="console" linenumbering="unnumbered">#{snippet_contents}</programlisting>
          <programlisting role="alternative" language="js-result" linenumbering="unnumbered">'just js result'</programlisting>
          <programlisting role="default has-js" language="console-result" linenumbering="unnumbered">#{result_contents}</programlisting>
          </preface>
        DOCBOOK
      end
      context 'the alternatives report' do
        it 'shows the request snippet' do
          expect(report).to include(<<~ASCIIDOC)
            === <stdin>: line 2: 39f76498cca438ba11af18a7075d24c9.adoc
            [source,console]
            ----
            GET /just_js_alternative
            ----
            |===
            | js | csharp | java

            | &check; | &cross; | &cross;
            |===
          ASCIIDOC
        end
        it 'shows the result snippet' do
          expect(report).to include(<<~ASCIIDOC)
            === <stdin>: line 7: c4f54085e4784ead2ef4a758d03edd16.adoc
            [source,console-result]
            ----
            {"just_js_result": {}}
            ----
            |===
            | js-result | csharp-result | java-result

            | &check; | &cross; | &cross;
            |===
          ASCIIDOC
        end
        it 'shows the result snippet after the request snippet' do
          expect(report.lines.grep(/stdin/)).to eq(
            [
              "=== <stdin>: line 2: 39f76498cca438ba11af18a7075d24c9.adoc\n",
              "=== <stdin>: line 7: c4f54085e4784ead2ef4a758d03edd16.adoc\n",
            ]
          )
        end
      end
      context 'the summary' do
        it 'counts the result' do
          expect(summary).to eq(
            console: {
              total: 2,
              alternatives: {
                js: { found: 2 },
                csharp: { found: 0 },
                java: { found: 0 },
              },
            }
          )
        end
      end
    end
    context 'when the alternative has characters that must be escaped' do
      include_context 'convert without logs'
      let(:input) { one_snippet }
      let(:snippet_contents) { 'GET /has_<' }
      it 'adds the alternative' do
        expect(converted).to include(<<~DOCBOOK.strip)
          var searchResponse = _client.Search&lt;Project&gt;(s =&gt; s
              .Query(q =&gt; q
                  .QueryString(m =&gt; m
                      .Query("foo bar")
                  )
              )
          );
        DOCBOOK
      end
    end
    context 'when the alternative includes another file' do
      include_context 'convert without logs'
      let(:input) { one_snippet }
      let(:snippet_contents) { 'GET /has_include' }
      it 'adds the alternative' do
        expect(converted).to include(<<~CSHARP.strip)
          Console.WriteLine("Hello World!");
        CSHARP
      end
    end
    context 'when the alternative is in a subdirectory' do
      include_context 'convert without logs'
      let(:input) { one_snippet }
      let(:snippet_contents) { 'GET /in_subdir' }
      it 'adds the alternative' do
        expect(converted).to include(<<~CSHARP.strip)
          Console.WriteLine("In subdir");
        CSHARP
      end
    end
    context 'when there are callouts' do
      include_context 'convert without logs'
      let(:input) do
        <<~ASCIIDOC
          [source,console]
          ----
          GET /there_are_callouts <1> <2>
          ----
          <1> a
          <2> b
        ASCIIDOC
      end
      it 'inserts the alternative code above the default code' do
        expect(converted).to include(<<~DOCBOOK.strip)
          <programlisting role="alternative" language="csharp" linenumbering="unnumbered">Console.WriteLine("there are callouts"); <co id="A0-CO1-1"/> <co id="A0-CO1-2"/></programlisting>
          <programlisting role="default has-csharp" language="console" linenumbering="unnumbered">GET /there_are_callouts <co id="CO1-1"/> <co id="CO1-2"/></programlisting>
        DOCBOOK
      end
      it 'inserts the alternative callouts above the default callouts' do
        expect(converted).to include(<<~DOCBOOK.strip)
          <calloutlist role="alternative lang-csharp">
          <callout arearefs="A0-CO1-1">
          <para>csharp a</para>
          </callout>
          <callout arearefs="A0-CO1-2">
          <para>csharp b</para>
          </callout>
          </calloutlist>
          <calloutlist role="default has-csharp lang-console">
          <callout arearefs="CO1-1">
          <para>a</para>
          </callout>
          <callout arearefs="CO1-2">
          <para>b</para>
          </callout>
          </calloutlist>
        DOCBOOK
      end
    end
    context 'when there is an error in the alternative' do
      include_context 'convert with logs'
      let(:input) { one_snippet }
      let(:snippet_contents) { 'GET /has_error' }
      it 'adds the alternative with the error text' do
        expect(converted).to include(<<~DOCBOOK.strip)
          include::missing.adoc[]
        DOCBOOK
      end
      it 'logs an error' do
        expect(logs).to eq(<<~LOG.strip)
          ERROR: resources/alternative_language_lookup/csharp/ded0ba409b7c66489d5833dc6aa5f696.adoc: line 3: include file not found: #{example_alternatives}/csharp/missing.adoc
        LOG
      end
    end
    context 'when the alternative has the wrong language' do
      include_context 'convert with logs'
      let(:input) { one_snippet }
      let(:snippet_contents) { 'GET /bad_language' }
      it "doesn't add the alternative" do
        expect(converted).not_to include('Console.WriteLine')
      end
      it 'logs a warning' do
        expect(logs).to eq(<<~LOG.strip)
          WARN: resources/alternative_language_lookup/csharp/fcac4757ba45b9b14f316eb9bda58584.adoc: line 2: Alternative language listing must have lang=csharp but was not_csharp.
        LOG
      end
    end
    context 'when the configuration has duplicates' do
      include_context 'convert with logs'
      let(:config) do
        <<~CSV
          console,js,#{example_alternatives}/js
          console,js,#{example_alternatives}/js
        CSV
      end
      let(:input) { one_snippet }
      let(:snippet_contents) { 'GET /will_fail' }
      it 'logs an error' do
        expect(logs).to eq(<<~LOG.strip)
          ERROR: invalid alternative_language_lookups, duplicate alternative_lang [js]
        LOG
      end
    end
  end
end
