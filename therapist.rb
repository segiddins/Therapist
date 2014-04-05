#!/usr/bin/env ruby
require 'octokit'
require 'tumblr_client'
require 'yaml'

class Hash
  def deep_symbolize_keys
    deep_transform_keys{ |key| key.to_sym rescue key }
  end
  def deep_transform_keys(&block)
    result = {}
    each do |key, value|
      result[yield(key)] = value.is_a?(Hash) ? value.deep_transform_keys(&block) : value
    end
    result
  end
end

module Therapist
  def self.client(token = nil)
    @client ||= Octokit::Client.new access_token: token, auto_paginate: true
  end

  class Markov
    def initialize(strings)
      @chain = {:TOKEN_START => []}
      parse strings
    end

    def generate
      words = []
      word = @chain[:TOKEN_START].sample
      while word && word != :TOKEN_END
        words.push(word)
        word = @chain[word].sample
      end
      words.join ' '
    end

    private

    def add_word_after_word(word1, word2)
      @chain[word1] ||= []
      @chain[word1].push(word2)
    end

    def parse(strings)
      strings.each do |string|
        words = string.gsub(/\s+/m, ' ').gsub(/^\s+|\s+$/m, '').split(' ').unshift(:TOKEN_START).push(:TOKEN_END) rescue []
        words.each_with_index do |word, i|
          add_word_after_word word, words[i+1] unless word == :TOKEN_END
        end
      end
    end
  end

  class Repository
    attr_accessor :name

    def initialize(name)
      @name = name
      issues = all_issues
      @markov_title = Markov.new(issues.map &:title)
      @markov_body = Markov.new(issues.map &:body)
    end

    def fake
      {
        title: @markov_title.generate,
        body: @markov_body.generate,
      }
    end

    private

    def all_issues(options = {})
      options = options.merge state: :all
      Therapist::client.issues(name, options) rescue []
    end
  end
end

CONFIG = YAML.load(File.read(File.expand_path('../therapist.yml', __FILE__))).deep_symbolize_keys
Therapist.client(CONFIG[:github][:access_token])
TUMBLR = Tumblr::Client.new CONFIG[:tumblr]

def post_fake_for_repo(repo)
  fake = repo.fake
  title = "New issue in #{repo.name}!"
  body = "<h3><a href='https://github.com/#{repo.name}'>#{repo.name}</a> - #{fake[:title]}</h3><p>#{fake[:body]}</p>"
  TUMBLR.text(CONFIG[:tumblr][:blog], state: :queue, title: title, body: body)
end

# repo = Therapist::Repository.new(CONFIG[:repos].sample)
# post_fake_for_repo repo

repos = CONFIG[:repos].map {|r| Therapist::Repository.new r}
100.times {post_fake_for_repo repos.sample}
