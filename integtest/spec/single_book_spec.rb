# frozen_string_literal: true

require 'fileutils'
require 'net/http'

RSpec.describe 'building a single book' do
  HEADER = <<~ASCIIDOC
    = Title

    [[chapter]]
    == Chapter
  ASCIIDOC

  let(:emdash)           { "\u2014" }
  let(:ellipsis)         { "\u2026" }
  let(:no_break_space)   { "\u00a0" }
  let(:zero_width_space) { "\u200b" }

  context 'for a minimal book' do
    shared_context 'expected' do |file_name|
      convert_single_before_context do |src|
        src.write file_name, <<~ASCIIDOC
          #{HEADER}
          This is a minimal viable asciidoc file for use with build_docs. The
          actual contents of this paragraph aren't important but having a
          paragraph here is required.
        ASCIIDOC
      end

      page_context 'index.html' do
        it 'has the right title' do
          expect(title).to eq('Title')
        end
        it 'has a link to the css' do
          expect(head).to include(<<~HTML)
            <link rel="stylesheet" type="text/css" href="/guide/static/styles.css" />
          HTML
        end
        it 'has a link to the js' do
          expect(contents).to include(<<~HTML)
            <script type="text/javascript" src="/guide/static/docs.js"></script>
          HTML
        end
        it 'has the right language' do
          expect(language).to eq('en')
        end
        it 'has an empty initial js state' do
          expect(initial_js_state).to be_empty
        end
      end
      page_context 'toc.html' do
        it "doesn't have the initail js state" do
          # because we didn't apply the template
          expect(initial_js_state).to be_nil
        end
      end
      page_context 'raw/index.html' do
        it "doesn't have the xml prolog" do
          expect(contents).not_to include('?xml')
        end
        it 'has the html5 doctype' do
          expect(contents).to include("<!DOCTYPE html>\n")
        end
        it "doesn't have any xmlns declarations" do
          expect(contents).not_to include('xmlns=')
        end
        it "doesn't have any xml:lang tags" do
          expect(contents).not_to include('xml:lang=')
        end
        it 'has a trailing newline' do
          expect(contents).to end_with("\n")
        end
        it 'has the right title' do
          expect(title).to eq('Title')
        end
        it "doesn't have the initial js state" do
          # because we don't apply the template which is how that gets in there
          expect(initial_js_state).to be_nil
        end
      end
      page_context 'chapter.html' do
        it 'has the right title' do
          expect(title).to eq('Chapter')
        end
      end
      page_context 'raw/chapter.html' do
        it 'has the right title' do
          expect(title).to eq('Chapter')
        end
      end
    end

    context 'when the file ends in .asciidoc' do
      include_context 'expected', 'minimal.asciidoc'
    end

    context 'when the file ends in .adoc' do
      include_context 'expected', 'minimal.adoc'
    end
  end

  context "when there isn't an elastic remote" do
    convert_single_before_context do |src|
      src.add_elastic_remote = false
      src.write 'index.asciidoc', <<~ASCIIDOC
        #{HEADER}
        This is a minimal viable asciidoc file for use with build_docs. The
        actual contents of this paragraph aren't important but having a
        paragraph here is required.
      ASCIIDOC
    end

    page_context 'chapter.html' do
      it 'has an "unknown" edit url' do
        expect(body).to include(<<~HTML.strip)
          <a href="unknown/edit/master/index.asciidoc" class="edit_me" title="Edit this page on GitHub" rel="nofollow">edit</a>
        HTML
      end
    end
  end

  context 'when one file includes another' do
    convert_single_before_context do |src|
      src.write 'included.asciidoc', 'I am tiny.'
      src.write 'index.asciidoc', <<~ASCIIDOC
        #{HEADER}
        I include "included" between here

        include::included.asciidoc[]

        and here.
      ASCIIDOC
    end

    page_context 'chapter.html' do
      it 'contains the index text' do
        expect(body).to include('I include "included"')
      end
      it 'contains the included text' do
        expect(body).to include('I am tiny.')
      end
    end
  end

  context 'for "interesting" inputs' do
    context 'for a book that contains an em dash' do
      convert_single_before_context do |src|
        src.write 'index.asciidoc', <<~ASCIIDOC
          #{HEADER}
          I have an em dash between some--words.
        ASCIIDOC
      end
      page_context 'chapter.html' do
        it 'the emdash is followed by a zero width space' do
          expect(body).to include("some#{emdash}#{zero_width_space}words")
        end
      end
    end
    context 'for a book that contains an ellipsis' do
      convert_single_before_context do |src|
        src.write 'index.asciidoc', <<~ASCIIDOC
          #{HEADER}
          I have an ellipsis between some...words.
        ASCIIDOC
      end
      page_context 'chapter.html' do
        it 'the ellipsis is followed by a zero width space' do
          expect(body).to include("some#{ellipsis}#{zero_width_space}words")
        end
      end
    end
    context 'for a book that contains an empty table cell' do
      convert_single_before_context do |src|
        src.write 'index.asciidoc', <<~ASCIIDOC
          #{HEADER}
          |===
          | Title | Other Title
          |       | Empty cell before this one
          |===
        ASCIIDOC
      end
      let(:empty_cell) do
        <<~HTML.strip
          <td align="left" valign="top">#{no_break_space}</td>
        HTML
      end
      let(:non_empty_cell) do
        <<~HTML.strip
          <td align="left" valign="top"><p>Empty cell before this one</p></td>
        HTML
      end
      page_context 'chapter.html' do
        it "the empty cell doesn't contain any other tags" do
          # We match on the empty cell followed by the non-empty cell so we
          # can be sure we're matching the right part of the table.
          expect(body).to include("<tr>#{empty_cell}#{non_empty_cell}</tr>")
        end
      end
    end
    context 'for a book that has a reference to a floating title' do
      convert_single_before_context do |src|
        src.write 'index.asciidoc', <<~ASCIIDOC
          #{HEADER}
          <<floater>>

          [float]
          [[floater]]
          == Floater
        ASCIIDOC
      end
      page_context 'chapter.html' do
        it "there isn't an edit me link in the link to the section" do
          expect(body).to include(<<~HTML.strip)
            <a class="xref" href="chapter.html#floater" title="Floater">Floater</a>
          HTML
        end
      end
    end
  end

  shared_context 'care admonition' do
    it 'copies the warning image' do
      expect(dest_file('images/icons/warning.png')).to file_exist
    end
    page_context 'chapter.html' do
      it 'includes the warning image' do
        expect(body).to include(
          '<img alt="Warning" src="images/icons/warning.png" />'
        )
      end
    end
  end
  context 'when the book contains beta[]' do
    include_context 'care admonition'
    convert_single_before_context do |src|
      src.write 'index.asciidoc', <<~ASCIIDOC
        #{HEADER}
        beta[]

        Words
      ASCIIDOC
    end
    page_context 'chapter.html' do
      it 'includes the beta text' do
        expect(body).to include(
          'The design and code is less mature than official GA features'
        )
      end
    end
  end
  context 'when the book contains experimental[]' do
    include_context 'care admonition'
    convert_single_before_context do |src|
      src.write 'index.asciidoc', <<~ASCIIDOC
        #{HEADER}
        experimental[]

        Words
      ASCIIDOC
    end
    page_context 'chapter.html' do
      it 'includes the experimental text' do
        expect(body).to include(
          'This functionality is experimental and may be changed or removed'
        )
      end
    end
  end

  context 'regarding the xpack tag' do
    let(:edit_me) do
      <<~HTML.lines.map { |l| ' ' + l.strip }.join.strip
        <a href="https://github.com/elastic/docs/edit/master/index.asciidoc"
           class="edit_me"
           title="Edit this page on GitHub"
           rel="nofollow">edit</a>
      HTML
    end
    let(:xpack_tag) do
      <<~HTML.strip
        <a class="xpack_tag" href="/subscriptions"></a>
      HTML
    end
    let(:rx) { %r{<#{h} class="title"><a id="#{id}"></a>(.+?)</#{h}>} }
    let(:title_tag) do
      return unless body

      m = rx.match(body)
      raise "Can't find title_tag with #{rx} in #{body}" unless m

      m[1]
    end
    shared_examples 'xpack tag title' do |has_tag|
      it 'contains the edit_me link' do
        expect(title_tag).to include(edit_me)
      end
      if has_tag
        it 'contains the xpack tag' do
          expect(title_tag).to include(xpack_tag)
        end
      else
        it "doesn't contain the xpack tag" do
          expect(title_tag).not_to include(xpack_tag)
        end
      end
    end
    shared_examples 'part page titles' do |onpart|
      page_context 'part.html' do
        let(:h) { 'h1' }
        let(:id) { 'part' }
        include_examples 'xpack tag title', onpart
      end
    end
    shared_examples 'chapter page titles' do |onchapter, onfloater, onsection|
      page_context 'chapter.html' do
        let(:h) { 'h2' }
        context 'the chapter title' do
          let(:id) { 'chapter' }
          include_examples 'xpack tag title', onchapter
        end
        context 'the section title' do
          let(:id) { 'section' }
          include_examples 'xpack tag title', onsection
        end
        context 'the float title' do
          let(:rx) { %r{<h2><a id="floater"></a>(.+?)</h2>} }
          include_examples 'xpack tag title', onfloater
        end
      end
    end

    def self.xpack_tag_context(onpart, onchapter, onfloater, onsection)
      convert_single_before_context do |src|
        index = xpack_tag_test_asciidoc onpart, onchapter, onfloater, onsection
        src.write 'index.asciidoc', index
      end

      include_examples 'part page titles', onpart
      include_examples 'chapter page titles', onchapter, onfloater, onsection
    end

    def self.xpack_tag_test_asciidoc(onpart, onchapter, onfloater, onsection)
      <<~ASCIIDOC
        = Title

        #{onpart ? '[role="xpack"]' : ''}
        [[part]]
        = Part

        #{onchapter ? '[role="xpack"]' : ''}
        [[chapter]]
        == Chapter

        Chapter words.

        [[floater]]
        [float]
        == #{onfloater ? '[xpack]#Floater#' : 'Floater'}

        Floater words.

        #{onsection ? '[role="xpack"]' : ''}
        [[section]]
        === Section

        Section words.
      ASCIIDOC
    end

    context 'when the xpack role is on a part' do
      xpack_tag_context true, false, false, false
    end
    context 'when the xpack role is on a chapter' do
      xpack_tag_context false, true, false, false
    end
    context 'when the xpack role is on a floating title' do
      xpack_tag_context false, false, true, false
    end
    context 'when the xpack role is on a section' do
      xpack_tag_context false, false, false, true
    end
    context 'when the xpack role is on everything' do
      xpack_tag_context true, true, true, true
    end
  end

  context 'for README.asciidoc' do
    convert_single_before_context do |src|
      root = File.expand_path('../../', __dir__)
      src.cp "#{root}/resources/cat.jpg", 'resources/cat.jpg'
      txt = File.open("#{root}/README.asciidoc", 'r:UTF-8', &:read)
      src.write 'index.asciidoc', txt
    end
    page_context 'index.html' do
      it 'has the right title' do
        expect(title).to eq('Docs HOWTO')
      end
    end
    page_context '_conditions_of_use.html' do
      it 'has the right title' do
        expect(title).to eq('Conditions of use')
      end
    end
    page_context 'setup.html' do
      it 'has the right title' do
        expect(title).to eq('Getting started')
      end
    end
    page_context 'build.html' do
      it 'has the right title' do
        expect(title).to eq('Building documentation')
      end
    end
    page_context 'asciidoc-guide.html' do
      it 'has the right title' do
        expect(title).to eq('Asciidoc Guide')
      end
    end
    # NOTE: There are lots more pages but it probably isn't worth asserting
    # on them too.
    file_context 'snippets/1.console' do
      let(:expected) do
        <<~CONSOLE
          GET /_search
          {
              "query": "foo bar"
          }
        CONSOLE
      end
      it 'has the right content' do
        expect(contents).to eq(expected)
      end
    end
    file_context 'resources/cat.jpg'
    file_context 'images/icons/caution.png'
    file_context 'images/icons/important.png'
    file_context 'images/icons/note.png'
    file_context 'images/icons/warning.png'
  end

  context 'for a book with console alternatives' do
    def self.index
      <<~ASCIIDOC
        = Title

        [[chapter]]
        == Chapter
        #{ConsoleExamples::README_LIKE}
      ASCIIDOC
    end
    convert_before do |src, dest|
      repo = src.repo 'src'
      from = repo.write 'index.asciidoc', index
      repo.commit 'commit outstanding'
      # Points java to a directory without any examples so we can report that.
      dest.prepare_convert_single(from, '.')
          .asciidoctor
          .alternatives('console', 'js', "#{__dir__}/../readme_examples/js")
          .alternatives(
            'console', 'csharp', "#{__dir__}/../readme_examples/csharp"
          )
          .alternatives('console', 'java', "#{__dir__}/helper")
          .convert
    end
    include_examples 'README-like console alternatives', 'raw', '.'
  end

  context 'for a book that uses {source_branch}' do
    INDEX = <<~ASCIIDOC
      = Title

      [[chapter]]
      == Chapter
      The branch is {source_branch}.
    ASCIIDOC
    def self.convert_with_source_branch_before_context(branch)
      convert_single_before_context do |src|
        unless branch == 'master'
          src.write 'dummy', 'needed so git is ok with switching branches'
          src.commit 'dummy'
          src.switch_to_new_branch branch
        end
        src.write 'index.asciidoc', INDEX
      end
    end
    shared_examples 'contains branch' do |branch|
      page_context 'chapter.html' do
        it 'contains the branch name' do
          expect(body).to include("The branch is #{branch}.")
        end
      end
    end
    context 'when the branch is master' do
      convert_with_source_branch_before_context 'master'
      include_examples 'contains branch', 'master'
    end
    context 'when the branch is 7.x' do
      convert_with_source_branch_before_context '7.x'
      include_examples 'contains branch', '7.x'
    end
    context 'when the branch is 1.5' do
      convert_with_source_branch_before_context '1.5'
      include_examples 'contains branch', '1.5'
    end
    context 'when the branch is 18.5' do
      convert_with_source_branch_before_context '18.5'
      include_examples 'contains branch', '18.5'
    end
    context 'when the branch is some_crazy_thing' do
      convert_with_source_branch_before_context 'some_crazy_thing'
      include_examples 'contains branch', 'master'
    end
    context 'when the branch is some_crazy_thing_7.x' do
      convert_with_source_branch_before_context 'some_crazy_thing_7.x'
      include_examples 'contains branch', '7.x'
    end
    context 'when the branch is some_crazy_thing_7_x' do
      convert_with_source_branch_before_context 'some_crazy_thing_7_x'
      include_examples 'contains branch', '7_x'
    end
  end

  context 'when run with --open' do
    include_context 'source and dest'
    before(:context) do
      repo = @src.repo_with_index 'repo', 'Words'
      @opened_docs =
        @dest.prepare_convert_single("#{repo.root}/index.asciidoc", '.').open
    end
    after(:context) do
      @opened_docs.exit
    end

    let(:static) { 'http://localhost:8000/guide/static' }
    let(:index) { Net::HTTP.get_response(URI('http://localhost:8000/guide/')) }
    let(:js) do
      Net::HTTP.get_response(URI("#{static}/docs.js"))
    end
    let(:css) do
      Net::HTTP.get_response(URI("#{static}/styles.css"))
    end

    it 'serves the book' do
      expect(index).to serve(doc_body(include(<<~HTML.strip)))
        <a href="chapter.html">Chapter
      HTML
    end

    context 'the js' do
      it 'is unminified' do
        expect(js).to serve(include(<<~JS))
          // Test comment used to detect unminifed JS in tests
        JS
      end
      it 'include hot module replacement for the css' do
        expect(js).to serve(include(<<~JS))
          // Setup hot module replacement for css if we're in dev mode.
        JS
      end
      it 'includes a source map' do
        expect(js).to serve(include('sourceMappingURL='))
      end
    end
    context 'the css' do
      it 'is unminified' do
        expect(css).to serve(include(<<~CSS))
          /* test comment used to detect unminified source */
        CSS
      end
      it 'includes a source map' do
        expect(css).to serve(include('sourceMappingURL='))
      end
    end
  end

  ##
  # When you point `build_docs` to a worktree it doesn't properly share the
  # worktree's parent into the docker container. This test simulates *that*.
  context 'when building a book in a worktree without its parent' do
    convert_before do |src, dest|
      repo = src.repo_with_index 'src', <<~ASCIIDOC
        I am in a worktree.
      ASCIIDOC
      worktree = src.path 'worktree'
      repo.create_worktree worktree, 'HEAD'
      FileUtils.rm_rf repo.root
      dest.convert_single "#{worktree}/index.asciidoc", '.', asciidoctor: true
    end
    page_context 'chapter.html' do
      it 'complains about not being able to find the repo toplevel' do
        expect(outputs[0]).to include("Couldn't find repo toplevel for /tmp/")
      end
      it 'has the worktree text' do
        expect(body).to include('I am in a worktree.')
      end
    end
  end

  context 'when a book contains migration warnings' do
    shared_context 'convert with migration warnings' do |suppress|
      convert_before do |src, dest|
        repo = src.repo_with_index 'src', <<~ASCIIDOC
          --------
          CODE HERE
          ----
        ASCIIDOC
        dest.convert_single "#{repo.root}/index.asciidoc", '.',
                            asciidoctor: true,
                            expect_failure: !suppress,
                            suppress_migration_warnings: suppress
      end
    end
    context 'and they are not suppressed' do
      include_context 'convert with migration warnings', false
      it 'fails with an appropriate error status' do
        expect(statuses[0]).to eq(255)
      end
      it 'complains about the MIGRATION warning' do
        expect(outputs[0]).to include(<<~LOG)
          asciidoctor: WARNING: index.asciidoc: line 7: MIGRATION: code block end doesn't match start
        LOG
      end
    end
    context 'and they are suppressed' do
      include_context 'convert with migration warnings', true
      it "doesn't complain about the MIGRATION warning" do
        expect(outputs[0]).not_to include(<<~LOG)
          asciidoctor: WARNING: index.asciidoc: line 7: MIGRATION: code block end doesn't match start
        LOG
      end
      page_context 'chapter.html' do
        it 'contains the snippet' do
          expect(body).to include('CODE HERE')
        end
      end
    end
  end

  context 'when an included file is missing' do
    convert_before do |src, dest|
      repo = src.repo_with_index 'src', <<~ASCIIDOC
        include::missing.asciidoc[]
      ASCIIDOC
      dest.convert_single "#{repo.root}/index.asciidoc", '.',
                          asciidoctor: true,
                          expect_failure: true
    end
    it 'fails with an appropriate error status' do
      expect(statuses[0]).to eq(255)
    end
    it 'logs the missing file' do
      expect(outputs[0]).to include(<<~LOG.strip)
        ERROR: index.asciidoc: line 5: include file not found: #{@src.repo('src').root}/missing.asciidoc
      LOG
    end
  end
end
