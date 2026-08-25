/// Newclid's problem corpus, parsed (Phase 167).
///
/// The corpus lives in `~/Code/var/Newclid/newclid/problems_datasets/` as
/// eleven plain-text files, two lines per problem: a name, then a body in
/// a one-line construction DSL. `newclid_translation.dart` turns a parsed
/// problem into a [Construction]; this file only reads the text, and it
/// is deliberately separate so a parse failure and a translation failure
/// are never the same error.
///
/// **The corpus is the reason this exists.** `docs/PLAN.md` records five
/// separate measurements ending in "the corpus is the limiting factor,
/// not the algebra" — the seven fixtures cannot show a prover feature
/// working or failing. 879 goals over problems drawn from the
/// JGEX/AlphaGeometry benchmark, the IMO and its shortlist can.
///
/// The grammar, read off the corpus rather than assumed (every one of the
/// 879 bodies fits it):
///
/// ```
/// body   := clause (';' clause)* ['|' clause (';' clause)*]
///            '?' goal (';' goal)*
/// clause := name+ '=' call (',' call)*
/// call   := macro arg*
/// goal   := predicate arg*
/// ```
///
/// A clause names the points it introduces on the left and constrains
/// them on the right. One call constrains a point to a curve; two calls
/// pin it to the crossing of both.
///
/// **A `|` opens the auxiliary section** — the points a solver is
/// expected to *construct*, not to be given. Fourteen bodies have one.
/// They are parsed and kept on [NewclidProblem.auxiliary] and are
/// deliberately **not** built: handing the prover the construction it
/// was supposed to find would measure the corpus's authors rather than
/// the prover. Phase 153's auxiliary search is what they are for.
///
/// **Several goals after one `?` are a conjunction**, and PLAN §"No
/// compound question" settles what to do with it: the verdict is
/// three-way about the figure, and a compound whose conjuncts split would
/// need a fourth answer about the question's shape. So a body with `n`
/// goals parses to `n` problems sharing one construction, named `foo`,
/// `foo#2`, … — measured one statement at a time, which is also how the
/// panel would ask them.
library;

/// One call on the right of a clause: `on_tline h b a c`.
class NewclidCall {
  const NewclidCall(this.macro, this.arguments);

  final String macro;
  final List<String> arguments;

  @override
  String toString() => '$macro ${arguments.join(' ')}';
}

/// One clause: the points it introduces, and what constrains them.
class NewclidClause {
  const NewclidClause(this.outputs, this.calls);

  /// The names left of the `=`. More than one when a single macro emits
  /// several points at once (`incenter2`, `cc_tangent`).
  final List<String> outputs;

  final List<NewclidCall> calls;

  @override
  String toString() => '${outputs.join(' ')} = ${calls.join(', ')}';
}

/// The statement after the `?`.
class NewclidGoal {
  const NewclidGoal(this.predicate, this.arguments);

  final String predicate;
  final List<String> arguments;

  @override
  String toString() => '$predicate ${arguments.join(' ')}';
}

/// One problem: a construction and a single goal.
class NewclidProblem {
  const NewclidProblem({
    required this.name,
    required this.source,
    required this.body,
    required this.clauses,
    required this.auxiliary,
    required this.goal,
  });

  /// The corpus name, suffixed `#2`, `#3`, … for the second and later
  /// goals of a conjunction.
  final String name;

  /// The file the problem came from, basename only.
  final String source;

  /// The raw body line, kept so a failure can quote what it failed on.
  final String body;

  final List<NewclidClause> clauses;

  /// The clauses after the `|`: the auxiliary construction the problem
  /// expects a solver to find. Never built — see the library comment.
  final List<NewclidClause> auxiliary;

  final NewclidGoal goal;

  @override
  String toString() => '$source:$name';
}

/// A body the grammar above does not cover.
///
/// Collected per problem rather than thrown out of the file, and never
/// dropped silently: a parser that skipped what it could not read would
/// make every number taken off the corpus a measurement of the parser.
/// Reported per body because that is the blast radius it should have —
/// a single malformed line once cost two whole files, 116 problems, and
/// the report said nothing about it.
class NewclidParseError implements Exception {
  const NewclidParseError(this.source, this.name, this.reason);

  final String source;
  final String name;
  final String reason;

  @override
  String toString() => 'NewclidParseError($source:$name): $reason';
}

/// What one corpus file held: the problems it yielded, and the bodies
/// that did not parse.
class NewclidCorpusFile {
  const NewclidCorpusFile(this.problems, this.errors);

  final List<NewclidProblem> problems;
  final List<NewclidParseError> errors;
}

/// Parses one corpus file: alternating name and body lines.
///
/// Blank bodies are skipped (the corpus has three), blank names are not.
NewclidCorpusFile parseNewclidProblems(String text, {required String source}) {
  final lines = text.split('\n');
  final problems = <NewclidProblem>[];
  final errors = <NewclidParseError>[];
  for (var i = 0; i + 1 < lines.length; i += 2) {
    final name = lines[i].trim();
    final body = lines[i + 1].trim();
    if (body.isEmpty) {
      continue;
    }
    try {
      problems.addAll(parseNewclidBody(name, body, source: source));
    } on NewclidParseError catch (error) {
      errors.add(error);
    }
  }
  return NewclidCorpusFile(problems, errors);
}

/// Parses one body into one problem per goal.
List<NewclidProblem> parseNewclidBody(
  String name,
  String body, {
  required String source,
}) {
  final halves = body.split('?');
  if (halves.length != 2) {
    throw NewclidParseError(
      source,
      name,
      'expected exactly one "?", found ${halves.length - 1}',
    );
  }
  final sections = halves[0].split('|');
  if (sections.length > 2) {
    throw NewclidParseError(source, name, 'more than one "|"');
  }
  final clauses = [
    for (final text in sections[0].split(';'))
      if (text.trim().isNotEmpty) _parseClause(text, source, name),
  ];
  if (clauses.isEmpty) {
    throw NewclidParseError(source, name, 'no clauses before the "?"');
  }
  final auxiliary = [
    if (sections.length == 2)
      for (final text in sections[1].split(';'))
        if (text.trim().isNotEmpty) _parseClause(text, source, name),
  ];
  final goals = [
    for (final text in halves[1].split(';'))
      if (text.trim().isNotEmpty) _parseGoal(text, source, name),
  ];
  if (goals.isEmpty) {
    throw NewclidParseError(source, name, 'no goal after the "?"');
  }
  return [
    for (var index = 0; index < goals.length; index++)
      NewclidProblem(
        name: index == 0 ? name : '$name#${index + 1}',
        source: source,
        body: body,
        clauses: clauses,
        auxiliary: auxiliary,
        goal: goals[index],
      ),
  ];
}

NewclidClause _parseClause(String text, String source, String name) {
  final sides = text.split('=');
  if (sides.length != 2) {
    throw NewclidParseError(source, name, 'clause without one "=": $text');
  }
  final outputs = sides[0].trim().split(RegExp(r'\s+'))
    ..removeWhere((token) => token.isEmpty);
  if (outputs.isEmpty) {
    throw NewclidParseError(source, name, 'clause names no point: $text');
  }
  final calls = <NewclidCall>[];
  for (final part in sides[1].split(',')) {
    final tokens = part.trim().split(RegExp(r'\s+'))
      ..removeWhere((token) => token.isEmpty);
    if (tokens.isEmpty) {
      throw NewclidParseError(source, name, 'clause with an empty call: $text');
    }
    calls.add(NewclidCall(tokens.first, tokens.sublist(1)));
  }
  return NewclidClause(outputs, calls);
}

NewclidGoal _parseGoal(String text, String source, String name) {
  final tokens = text.trim().split(RegExp(r'\s+'))
    ..removeWhere((token) => token.isEmpty);
  if (tokens.isEmpty) {
    throw NewclidParseError(source, name, 'empty goal');
  }
  return NewclidGoal(tokens.first, tokens.sublist(1));
}
