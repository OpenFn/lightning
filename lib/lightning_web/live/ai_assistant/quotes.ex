defmodule LightningWeb.AiAssistant.Quotes do
  @moduledoc """
  Quotes about AI and human responsibility for the AI Assistant onboarding.
  """

  @type quote :: %{
          required(:quote) => String.t(),
          required(:author) => String.t(),
          optional(:source_attribute) => String.t(),
          required(:source_link) => String.t(),
          optional(:enabled) => boolean()
        }

  @quotes [
    %{
      quote: "What hath God wrought?",
      author: "Samuel Morse",
      source_attribute: "Samuel Morse in the first telegraph message",
      source_link: "https://www.history.com",
      enabled: true
    },
    %{
      quote: "All models are wrong, but some are useful",
      author: "George Box",
      source_attribute: "Wikipedia",
      source_link: "https://en.wikipedia.org/wiki/All_models_are_wrong",
      enabled: true
    },
    %{
      quote: "AI is neither artificial nor intelligent",
      author: "Kate Crawford",
      source_link:
        "https://www.wired.com/story/researcher-says-ai-not-artificial-intelligent/",
      enabled: true
    },
    %{
      quote: "With big data comes big responsibilities",
      author: "Kate Crawford",
      source_link:
        "https://www.technologyreview.com/2011/10/05/190904/with-big-data-comes-big-responsibilities",
      enabled: true
    },
    %{
      quote: "AI is holding the internet hostage",
      author: "Bryan Walsh",
      source_link:
        "https://www.vox.com/technology/352849/openai-chatgpt-google-meta-artificial-intelligence-vox-media-chatbots",
      enabled: true
    },
    %{
      quote: "Remember the human",
      author: "OpenFn Responsible AI Policy",
      source_link: "https://www.openfn.org/ai",
      enabled: true
    },
    %{
      quote: "Be skeptical, but don't be cynical",
      author: "OpenFn Responsible AI Policy",
      source_link: "https://www.openfn.org/ai",
      enabled: true
    },
    %{
      quote:
        "Out of the crooked timber of humanity no straight thing was ever made",
      author: "Emmanuel Kant",
      source_link:
        "https://www.goodreads.com/quotes/74482-out-of-the-crooked-timber-of-humanity-no-straight-thing"
    },
    %{
      quote: "The more helpful our phones get, the harder it is to be ourselves",
      author: "Brain Chrstian",
      source_attribute: "The most human Human",
      source_link:
        "https://www.goodreads.com/book/show/8884400-the-most-human-human"
    },
    %{
      quote:
        "If a machine can think, it might think more intelligently than we do, and then where should we be?",
      author: "Alan Turing",
      source_link:
        "https://turingarchive.kings.cam.ac.uk/publications-lectures-and-talks-amtb/amt-b-5"
    },
    %{
      quote:
        "If you make an algorithm, and let it optimise for a certain value, then it won't care what you really want",
      author: "Tom Chivers",
      source_link:
        "https://forum.effectivealtruism.org/posts/feNJWCo4LbsoKbRon/interview-with-tom-chivers-ai-is-a-plausible-existential"
    },
    %{
      quote:
        "By far the greatest danger of Artificial Intelligence is that people conclude too early that they understand it",
      author: "Eliezer Yudkowsky",
      source_attribute:
        "Artificial Intelligence as a Positive and Negative Factor in Global Risk",
      source_link:
        "https://zoo.cs.yale.edu/classes/cs671/12f/12f-papers/yudkowsky-ai-pos-neg-factor.pdf"
    },
    %{
      quote:
        "The AI does not hate you, nor does it love you, but you are made out of atoms which it can use for something else",
      author: "Eliezer Yudkowsky",
      source_attribute:
        "Artificial Intelligence as a Positive and Negative Factor in Global Risk",
      source_link:
        "https://zoo.cs.yale.edu/classes/cs671/12f/12f-papers/yudkowsky-ai-pos-neg-factor.pdf"
    },
    %{
      quote:
        "World domination is such an ugly phrase. I prefer to call it world optimisation",
      author: "Eliezer Yudkowsky",
      source_link: "https://hpmor.com/"
    },
    %{
      quote: "AI is not ultimately responsible for its output: we are",
      author: "OpenFn Responsible AI Policy",
      source_link: "https://www.openfn.org/ai"
    }
  ]

  @doc """
  Returns enabled quotes only.
  """
  @spec enabled() :: [quote()]
  def enabled do
    Enum.filter(@quotes, fn quote ->
      Map.get(quote, :enabled, false)
    end)
  end

  @doc """
  Returns a random enabled quote.
  """
  @spec random_enabled() :: quote()
  def random_enabled do
    enabled()
    |> Enum.random()
  end
end
