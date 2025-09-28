// Tree-sitter grammar for Ghostlang
// Based on the syntax demonstrated in the plugin examples

module.exports = grammar({
  name: 'ghostlang',

  rules: {
    source_file: $ => repeat(choice(
      $.variable_declaration,
      $.function_declaration,
      $.if_statement,
      $.while_statement,
      $.for_statement,
      $.expression_statement,
      $.block_statement,
      $.return_statement,
      $.empty_statement,
      $.comment
    )),

    statement: $ => choice(
      $.variable_declaration,
      $.function_declaration,
      $.if_statement,
      $.while_statement,
      $.for_statement,
      $.expression_statement,
      $.block_statement,
      $.return_statement,
      $.empty_statement
    ),

    // Variable declarations: var x = 5;
    variable_declaration: $ => seq(
      'var',
      field('name', $.identifier),
      '=',
      field('value', $._expression_base),
      ';'
    ),

    // Variable declarations without semicolon (for use in for loops)
    for_variable_declaration: $ => seq(
      'var',
      field('name', $.identifier),
      '=',
      field('value', $._expression_base)
    ),

    // Function declarations: function name() { ... }
    function_declaration: $ => seq(
      'function',
      field('name', $.identifier),
      field('parameters', $.parameter_list),
      field('body', $.block_statement)
    ),

    parameter_list: $ => seq(
      '(',
      optional(seq(
        $.identifier,
        repeat(seq(',', $.identifier))
      )),
      ')'
    ),

    // Control flow statements
    if_statement: $ => prec.right(seq(
      'if',
      '(',
      field('condition', $._expression_base),
      ')',
      field('then', choice(
        $.variable_declaration,
        $.function_declaration,
        $.if_statement,
        $.while_statement,
        $.for_statement,
        $.expression_statement,
        $.block_statement,
        $.return_statement,
        $.empty_statement
      )),
      optional(seq('else', field('else', choice(
        $.variable_declaration,
        $.function_declaration,
        $.if_statement,
        $.while_statement,
        $.for_statement,
        $.expression_statement,
        $.block_statement,
        $.return_statement,
        $.empty_statement
      ))))
    )),

    while_statement: $ => seq(
      'while',
      '(',
      field('condition', $._expression_base),
      ')',
      field('body', choice(
        $.variable_declaration,
        $.function_declaration,
        $.if_statement,
        $.while_statement,
        $.for_statement,
        $.expression_statement,
        $.block_statement,
        $.return_statement,
        $.empty_statement
      ))
    ),

    for_statement: $ => prec(10, seq(
      'for',
      '(',
      choice(
        seq(
          field('init', optional(alias($.for_variable_declaration, $.variable_declaration))),
          ';',
          field('condition', optional($._expression_base)),
          ';',
          field('update', optional($._expression_base))
        ),
        seq(
          'var',
          field('variable', $.identifier),
          'in',
          field('iterable', $._expression_base)
        )
      ),
      ')',
      field('body', choice(
        $.variable_declaration,
        $.function_declaration,
        $.if_statement,
        $.while_statement,
        $.for_statement,
        $.expression_statement,
        $.block_statement,
        $.return_statement,
        $.empty_statement
      ))
    )),

    return_statement: $ => seq(
      'return',
      optional($._expression_base),
      ';'
    ),

    expression_statement: $ => seq(
      $._expression_base,
      ';'
    ),

    block_statement: $ => seq(
      '{',
      repeat(choice(
        $.variable_declaration,
        $.function_declaration,
        $.if_statement,
        $.while_statement,
        $.for_statement,
        $.expression_statement,
        $.block_statement,
        $.return_statement,
        $.empty_statement,
        $.comment
      )),
      '}'
    ),

    empty_statement: $ => ';',

    // Base expression rule that matches test expectations
    _expression_base: $ => choice(
      $.assignment_expression,
      $.conditional_expression,
      $.logical_or_expression,
      $.logical_and_expression,
      $.equality_expression,
      $.relational_expression,
      $.additive_expression,
      $.multiplicative_expression,
      $.unary_expression,
      $.call_expression,
      $.member_expression,
      $.subscript_expression,
      $.object_literal,
      $.array_literal,
      $.identifier,
      $.number_literal,
      $.string_literal,
      $.boolean_literal,
      $.null_literal,
      seq('(', $._expression_base, ')')
    ),

    // Expressions
    expression: $ => $._expression_base,

    assignment_expression: $ => prec.right(1, choice(
      seq(
        field('left', $._expression_base),
        field('operator', choice('=', '+=', '-=', '*=', '/=')),
        field('right', $._expression_base)
      ),
      seq(
        field('left', $._expression_base),
        field('operator', alias(choice('++', '--'), $.string))
      )
    )),

    conditional_expression: $ => prec.right(2, seq(
      $._expression_base,
      '?',
      $._expression_base,
      ':',
      $._expression_base
    )),

    logical_or_expression: $ => prec.left(3, seq(
      $._expression_base, '||', $._expression_base
    )),

    logical_and_expression: $ => prec.left(4, seq(
      $._expression_base, '&&', $._expression_base
    )),

    equality_expression: $ => prec.left(5, seq(
      $._expression_base, choice('==', '!='), $._expression_base
    )),

    relational_expression: $ => prec.left(6, seq(
      $._expression_base, choice('<', '>', '<=', '>='), $._expression_base
    )),

    additive_expression: $ => prec.left(7, seq(
      $._expression_base, choice('+', '-'), $._expression_base
    )),

    multiplicative_expression: $ => prec.left(8, seq(
      $._expression_base, choice('*', '/', '%'), $._expression_base
    )),

    unary_expression: $ => prec(9, seq(
      choice('+', '-', '!'), $._expression_base
    )),

    call_expression: $ => prec.left(10, seq(
      field('function', $._expression_base),
      field('arguments', $.argument_list)
    )),

    member_expression: $ => prec.left(10, seq(
      field('object', $._expression_base),
      '.',
      field('property', $.identifier)
    )),

    subscript_expression: $ => prec.left(10, seq(
      field('object', $._expression_base),
      '[',
      field('index', $._expression_base),
      ']'
    )),

    argument_list: $ => seq(
      '(',
      optional(seq(
        $._expression_base,
        repeat(seq(',', $._expression_base))
      )),
      ')'
    ),


    // Object literals: { key: value, ... }
    object_literal: $ => seq(
      '{',
      optional(seq(
        $.object_member,
        repeat(seq(',', $.object_member)),
        optional(',')
      )),
      '}'
    ),

    object_member: $ => seq(
      choice(
        $.identifier,
        $.string_literal
      ),
      ':',
      $._expression_base
    ),

    // Array literals: [1, 2, 3]
    array_literal: $ => seq(
      '[',
      optional(seq(
        $._expression_base,
        repeat(seq(',', $._expression_base)),
        optional(',')
      )),
      ']'
    ),

    // Literals
    identifier: $ => token(prec(-1, /[a-zA-Z_][a-zA-Z0-9_]*/)),

    number_literal: $ => choice(
      /\d+/,
      /\d+\.\d+/,
      /\d*\.?\d+[eE][+-]?\d+/
    ),

    string_literal: $ => choice(
      seq('"', repeat(choice(/[^"\\]/, $.escape_sequence)), '"'),
      seq("'", repeat(choice(/[^'\\]/, $.escape_sequence)), "'")
    ),

    escape_sequence: $ => seq(
      '\\',
      choice(
        /[\\'"nrtbfav0]/,
        /x[0-9a-fA-F]{2}/,
        /u[0-9a-fA-F]{4}/,
        /U[0-9a-fA-F]{8}/
      )
    ),

    boolean_literal: $ => choice('true', 'false'),
    null_literal: $ => 'null',

    // Comments
    comment: $ => token(choice(
      seq('//', /.*/),
      seq('/*', /[^*]*\*+([^/*][^*]*\*+)*/, '/')
    )),

    // Whitespace
    _whitespace: $ => /\s+/
  },

  extras: $ => [
    $.comment,
    $._whitespace
  ],

  conflicts: $ => [
    // Handle potential ambiguities
    [$.assignment_expression, $.conditional_expression],
    [$.call_expression, $.member_expression],
    [$.block_statement, $.object_literal],
    [$.expression]
  ],

  word: $ => $.identifier
});