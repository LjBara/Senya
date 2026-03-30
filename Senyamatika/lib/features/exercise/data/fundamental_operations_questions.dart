/// Seed questions for the Fundamental Operations comprehensive exercise.
/// This single exercise covers Addition, Subtraction, Multiplication, and Division.
/// Progress is recorded under all four lesson names (see ExerciseController).
///
/// Supported types: multiple_choice, matching, drag_drop_match,
///   drag_drop_order, drag_drop_sequence.
class FundamentalOperationsQuestions {
  const FundamentalOperationsQuestions._();

  /// Lesson names that all receive the score when this exercise is completed.
  static const List<String> allLessonNames = [
    'Addition',
    'Subtraction',
    'Multiplication',
    'Division',
  ];

  static const List<Map<String, dynamic>> all = [
    // ADDITION
    {
      'id': 1,
      'type': 'multiple_choice',
      'operation': 'addition',
      'question': 'What is 7 + 5?',
      'correctAnswer': 1,
      'options': ['11', '12', '13', '14'],
      'explanation': '7 + 5 = 12',
    },
    {
      'id': 2,
      'type': 'multiple_choice',
      'operation': 'addition',
      'question': 'How many apples in total?',
      'leftObjects': ['🍎', '🍎', '🍎', '🍎'],
      'rightObjects': ['🍎', '🍎', '🍎'],
      'leftCount': 4,
      'rightCount': 3,
      'correctAnswer': 2,
      'options': ['5', '6', '7', '8'],
      'explanation': '4 apples + 3 apples = 7 apples',
    },
    {
      'id': 3,
      'type': 'drag_drop_match',
      'operation': 'addition',
      'question': 'Match each addition with the correct sum:',
      'leftItems': ['12 + 5', '20 + 13', '15 + 15', '24 + 6'],
      'rightItems': ['17', '33', '30', '30'],
      'correctMatches': [0, 1, 2, 2],
      'explanation': '12+5=17, 20+13=33, 15+15=30, 24+6=30',
    },
    // SUBTRACTION
    {
      'id': 4,
      'type': 'multiple_choice',
      'operation': 'subtraction',
      'question': 'What is 15 - 7?',
      'correctAnswer': 2,
      'options': ['6', '7', '8', '9'],
      'explanation': '15 - 7 = 8',
    },
    {
      'id': 5,
      'type': 'multiple_choice',
      'operation': 'subtraction',
      'question': 'How many are left?',
      'totalObjects': ['🍎', '🍎', '🍎', '🍎', '🍎', '🍎', '🍎', '🍎'],
      'removeCount': 3,
      'totalCount': 8,
      'correctAnswer': 1,
      'options': ['4', '5', '6', '7'],
      'explanation': '8 - 3 = 5 apples left',
    },
    {
      'id': 6,
      'type': 'multiple_choice',
      'operation': 'subtraction',
      'question': 'Mika had 25 candies. She ate 8. How many are left?',
      'correctAnswer': 1,
      'options': ['15', '17', '18', '20'],
      'explanation': '25 - 8 = 17 candies left',
    },
    // MULTIPLICATION
    {
      'id': 7,
      'type': 'multiple_choice',
      'operation': 'multiplication',
      'question': 'What is 6 × 4?',
      'correctAnswer': 2,
      'options': ['20', '22', '24', '26'],
      'explanation': '6 × 4 = 24',
    },
    {
      'id': 8,
      'type': 'drag_drop_order',
      'operation': 'multiplication',
      'question': 'Arrange the repeated addition for 3 × 4:',
      'items': ['4', '+', '4', '+', '4'],
      'correctOrder': ['4', '+', '4', '+', '4'],
      'explanation': '3 × 4 means 4 + 4 + 4',
    },
    {
      'id': 9,
      'type': 'multiple_choice',
      'operation': 'multiplication',
      'question': 'A box has 8 eggs. How many eggs in 5 boxes?',
      'correctAnswer': 2,
      'options': ['35', '38', '40', '45'],
      'explanation': '8 × 5 = 40 eggs',
    },
    // DIVISION
    {
      'id': 10,
      'type': 'multiple_choice',
      'operation': 'division',
      'question': 'What is 24 ÷ 6?',
      'correctAnswer': 0,
      'options': ['4', '5', '6', '7'],
      'explanation': '24 ÷ 6 = 4',
    },
    {
      'id': 11,
      'type': 'drag_drop_match',
      'operation': 'division',
      'question': 'Match each division with the correct quotient:',
      'leftItems': ['15 ÷ 3', '20 ÷ 4', '18 ÷ 3', '12 ÷ 2'],
      'rightItems': ['5', '5', '6', '6'],
      'correctMatches': [0, 0, 1, 1],
      'explanation': '15÷3=5, 20÷4=5, 18÷3=6, 12÷2=6',
    },
    {
      'id': 12,
      'type': 'multiple_choice',
      'operation': 'division',
      'question': '36 candies shared equally among 4 children. How many each?',
      'correctAnswer': 1,
      'options': ['8', '9', '10', '12'],
      'explanation': '36 ÷ 4 = 9 candies each',
    },
    // MIXED
    {
      'id': 13,
      'type': 'matching',
      'operation': 'mixed',
      'question': 'Match each equation with the correct answer:',
      'leftItems': ['8 + 5', '15 - 7', '4 × 3', '18 ÷ 2'],
      'rightItems': ['13', '8', '12', '9'],
      'correctMatches': [0, 1, 2, 3],
      'explanation': '8+5=13, 15-7=8, 4×3=12, 18÷2=9',
    },
    {
      'id': 14,
      'type': 'drag_drop_sequence',
      'operation': 'mixed',
      'question': 'Complete the equations with the correct numbers:',
      'sequence': ['5 + __ = 12', '__ × 3 = 18', '20 - __ = 11', '__ ÷ 4 = 5'],
      'availableNumbers': ['7', '6', '9', '20', '8'],
      'correctAnswer': ['7', '6', '9', '20'],
      'blankPositions': [0, 1, 2, 3],
      'explanation': '5+7=12, 6×3=18, 20-9=11, 20÷4=5',
    },
    {
      'id': 15,
      'type': 'multiple_choice',
      'operation': 'mixed',
      'question': 'Ana has 24 apples. She gives 6 to Maria and divides the rest equally among 3 friends. How many does each friend get?',
      'correctAnswer': 1,
      'options': ['5', '6', '7', '8'],
      'explanation': '24 - 6 = 18, then 18 ÷ 3 = 6 apples each.',
    },
  ];
}
