# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/maven/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Maven::MetadataFinder do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [{
        file: "pom.xml",
        requirement: dependency_version,
        groups: [],
        source: dependency_source
      }],
      package_manager: "maven"
    )
  end
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_name) { "com.google.guava:guava" }
  let(:dependency_version) { "23.3-jre" }
  let(:dependency_source) do
    { type: "maven_repo", url: "https://repo.maven.apache.org/maven2" }
  end

  describe "#source_url" do
    subject(:source_url) { finder.source_url }
    let(:maven_url) do
      "https://repo.maven.apache.org/maven2/com/google/guava/"\
      "guava/23.3-jre/guava-23.3-jre.pom"
    end
    let(:maven_response) { fixture("poms", "guava-23.3-jre.xml") }

    before do
      stub_request(:get, maven_url).to_return(status: 200, body: maven_response)
    end

    context "when the github link is buried in the pom" do
      let(:maven_response) { fixture("poms", "guava-23.3-jre.xml") }

      it { is_expected.to eq("https://github.com/google/guava") }

      it "caches the call to maven" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, maven_url).once
      end
    end

    context "when there is no github link in the pom" do
      let(:maven_response) { fixture("poms", "okhttp-3.10.0.xml") }
      let(:dependency_name) { "com.squareup.okhttp3:okhttp" }
      let(:dependency_version) { "3.10.0" }
      let(:maven_url) do
        "https://repo.maven.apache.org/maven2/com/squareup/okhttp3/"\
        "okhttp/3.10.0/okhttp-3.10.0.pom"
      end
      let(:parent_url) do
        "https://repo.maven.apache.org/maven2/com/squareup/okhttp3/"\
        "parent/3.10.0/parent-3.10.0.pom"
      end

      context "but there is in the parent" do
        before do
          stub_request(:get, parent_url).
            to_return(
              status: 200,
              body: fixture("poms", "parent-3.10.0.xml")
            )
        end

        it { is_expected.to eq("https://github.com/square/okhttp") }

        it "caches the call to maven" do
          2.times { source_url }
          expect(WebMock).to have_requested(:get, maven_url).once
        end

        context "that doesn't match the name of the artifact" do
          let(:url) { "https://api.github.com/repos/square/unrelated_name" }
          before do
            stub_request(:get, parent_url).
              to_return(
                status: 200,
                body: fixture("poms", "parent-unrelated-3.10.0.xml")
              )

            allow_any_instance_of(Dependabot::FileFetchers::Base).
              to receive(:commit).and_return("sha")
            stub_request(:get, url + "/contents/?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github", repo_contents_fixture_nm),
                headers: { "content-type" => "application/json" }
              )
          end

          context "and doesn't have a subdirectory with its name" do
            let(:repo_contents_fixture_nm) { "contents_js_npm.json" }
            it { is_expected.to be_nil }
          end

          context "and does have a subdirectory with its name" do
            let(:repo_contents_fixture_nm) { "contents_java_with_subdir.json" }
            it { is_expected.to eq("https://github.com/square/unrelated_name") }
          end

          context "and the repo 404s" do
            before do
              allow_any_instance_of(Dependabot::FileFetchers::Base).
                to receive(:commit).and_call_original
              stub_request(:get, url).
                with(headers: { "Authorization" => "token token" }).
                to_return(
                  status: 404,
                  body: fixture("github", "not_found.json"),
                  headers: { "content-type" => "application/json" }
                )
            end
            let(:repo_contents_fixture_nm) { "not_found.json" }

            it { is_expected.to be_nil }
          end
        end
      end

      context "and there isn't in the parent, either" do
        before do
          stub_request(:get, parent_url).to_return(status: 404, body: "")
        end

        it { is_expected.to be_nil }

        it "caches the call to maven" do
          2.times { source_url }
          expect(WebMock).to have_requested(:get, maven_url).once
        end
      end
    end

    context "when the github link includes a property" do
      let(:maven_response) { fixture("poms", "property_url_pom.xml") }
      it { is_expected.to eq("https://github.com/davidB/maven-scala-plugin") }

      context "that is nested" do
        let(:maven_response) do
          fixture("poms", "nested_property_url_pom.xml")
        end

        it do
          is_expected.to eq("https://github.com/apache/maven-checkstyle-plugin")
        end
      end
    end

    context "when there is a github link in the maven response" do
      let(:maven_response) do
        fixture("poms", "mockito-core-2.11.0.xml")
      end

      it { is_expected.to eq("https://github.com/mockito/mockito") }

      it "caches the call to maven" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, maven_url).once
      end
    end

    context "when using a custom registry" do
      let(:dependency_source) do
        { type: "maven_repo", url: "https://custom.registry.org/maven2" }
      end
      let(:maven_url) do
        "https://custom.registry.org/maven2/com/google/guava/"\
        "guava/23.3-jre/guava-23.3-jre.pom"
      end
      let(:maven_response) do
        fixture("poms", "mockito-core-2.11.0.xml")
      end

      it { is_expected.to eq("https://github.com/mockito/mockito") }

      context "with credentials" do
        let(:credentials) do
          [
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
              "type" => "maven_repository",
              "url" => "https://custom.registry.org/maven2"
            }
          ]
        end

        it { is_expected.to eq("https://github.com/mockito/mockito") }

        context "that include a username and password" do
          let(:credentials) do
            [
              {
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              },
              {
                "type" => "maven_repository",
                "url" => "https://custom.registry.org/maven2",
                "username" => "dependabot",
                "password" => "dependabotPassword"
              }
            ]
          end
          before do
            stub_request(:get, maven_url).to_return(status: 404)
            stub_request(:get, maven_url).
              with(basic_auth: %w(dependabot dependabotPassword)).
              to_return(status: 200, body: maven_response)
          end

          it { is_expected.to eq("https://github.com/mockito/mockito") }
        end
      end
    end

    context "when the Maven link resolves to a redirect" do
      let(:redirect_url) do
        "https://repo1.maven.org/maven2/org/mockito/mockito-core/2.11.0/"\
        "mockito-core-2.11.0.pom"
      end
      let(:maven_response) do
        fixture("poms", "mockito-core-2.11.0.xml")
      end

      before do
        stub_request(:get, maven_url).
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(status: 200, body: maven_response)
      end

      it { is_expected.to eq("https://github.com/mockito/mockito") }
    end
  end
end