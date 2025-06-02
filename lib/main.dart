// ============================================================================
// 必要なライブラリのインポート
// ============================================================================

// Flutter UIフレームワークの基本ライブラリ（WidgetやMaterialDesignのコンポーネント）
import 'package:flutter/material.dart';

// HTTP通信を行うためのライブラリ（バックエンドサーバーとの通信に使用）
import 'package:http/http.dart' as http;

// HTTPリクエストのContent-Typeを指定するためのライブラリ（画像ファイルのMIMEタイプ指定）
import 'package:http_parser/http_parser.dart';

// JSON形式データの変換処理（バックエンドからのレスポンス解析）
import 'dart:convert';

// バイナリデータ（画像ファイル）を扱うためのデータ型
import 'dart:typed_data';

// デバイスのギャラリーやカメラから画像を選択するためのライブラリ
import 'package:image_picker/image_picker.dart';

// アプリ内のアセットファイル（画像・音声等）にアクセスするためのライブラリ
import 'package:flutter/services.dart';

// ============================================================================
// アプリケーションのエントリーポイント
// ============================================================================

/// アプリケーション開始時に最初に実行される関数
/// MyAppクラスをFlutterエンジンに渡してアプリケーションを起動
void main() {
  runApp(const MyApp());
}

// ============================================================================
// アプリケーション全体の設定を管理するクラス
// ============================================================================

/// StatelessWidget = 状態を持たない静的なWidget
/// アプリ全体のテーマ設定、タイトル、最初に表示する画面を定義
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  /// このWidgetのUI構造を定義するメソッド
  /// MaterialAppはGoogleのMaterial Designに基づいたアプリの基本構造を提供
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image Composer', // アプリのタイトル（タスクスイッチャーで表示）
      
      // アプリ全体のテーマ設定
      theme: ThemeData(
        // 青色をベースにしたカラーパレットを自動生成
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        // Material Design 3のスタイルを使用
        useMaterial3: true,
      ),
      
      // アプリ起動時に最初に表示される画面を指定
      home: const MyHomePage(),
    );
  }
}

// ============================================================================
// メイン画面を管理するクラス
// ============================================================================

/// StatefulWidget = 状態を持つ動的なWidget
/// ユーザーの操作によって画面の内容が変化する場合に使用
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  /// このWidgetの状態を管理するStateクラスを作成
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

// ============================================================================
// メイン画面の状態と処理を管理するクラス
// ============================================================================

/// MyHomePageの状態管理を行うクラス
/// ユーザーが選択した画像、バックエンドからの結果、処理状況などを管理
class _MyHomePageState extends State<MyHomePage> {
  
  // === アプリケーションの状態を管理する変数群 ===
  
  /// ユーザーがギャラリーから選択した画像のバイナリデータ
  /// null = まだ画像が選択されていない状態
  Uint8List? _selectedImage;
  
  /// バックエンドで合成処理された画像のURL
  /// バックエンドから返されるJSONレスポンスに含まれる画像のパス
  String? _composedImageUrl;
  
  /// バックエンドでの処理中フラグ
  /// true = 現在処理中（ボタンを無効化、ローディング表示）
  /// false = 処理していない（通常状態）
  bool _isProcessing = false;
  
  /// アセットから読み込んだ背景画像のバイナリデータ
  /// バックエンドに送信する固定の背景画像
  Uint8List? _backgroundImage;

  // === アセットファイルのパス設定 ===
  
  /// プロジェクト内の背景画像ファイルのパス
  /// assets/images/フォルダに配置したJPG画像を指定
  /// pubspec.yamlでアセット登録が必要
  static const String _backgroundImagePath = "wanted.jpg";

  // ============================================================================
  // Widget初期化処理
  // ============================================================================
  
  /// Widgetが作成された直後に1回だけ呼ばれる初期化メソッド
  /// アプリ起動時に必要な初期処理を実行
  @override
  void initState() {
    super.initState(); // 親クラスの初期化を実行
    _loadBackgroundImage(); // 背景画像の読み込み処理を開始
  }

  /// アセットフォルダから背景画像を読み込む非同期処理
  /// エラーハンドリングを含めて安全に画像を読み込み
  Future<void> _loadBackgroundImage() async {
    try {
      // rootBundle.load() = アセットファイルをByteDataとして読み込み
      final bytes = await rootBundle.load(_backgroundImagePath);
      
      // setStateで状態を更新し、UIの再描画をトリガー
      setState(() {
        // ByteDataをUint8List（バイナリ配列）に変換して保存
        _backgroundImage = bytes.buffer.asUint8List();
      });
      
    } catch (e) {
      // ファイルが見つからない、権限エラーなどの場合のエラーハンドリング
      print('背景画像の読み込みに失敗しました: $e');
      // 本格的なアプリでは、ユーザーに分かりやすいエラーメッセージを表示すべき
    }
  }

  // ============================================================================
  // 画像選択処理
  // ============================================================================
  
  /// ユーザーがギャラリーから画像を選択する処理
  /// ImagePickerライブラリを使用してデバイスの画像ライブラリにアクセス
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final imageBytes = await pickedFile.readAsBytes();
      setState(() {
        _selectedImage = imageBytes;
        _composedImageUrl = null;
      });
    }
  }

  // ============================================================================
  // バックエンド通信・画像合成処理
  // ============================================================================
  
  /// 選択した画像と背景画像をバックエンドに送信して合成処理を実行
  /// HTTP マルチパートリクエストを使用してファイルアップロードを行う
  Future<void> _composeImages() async {
    
    // === 事前チェック：必要な画像が揃っているか確認 ===
    
    // ユーザーが画像を選択していない場合はエラー
    if (_selectedImage == null) {
      _showMessage('画像を選択してください', isError: true);
      return; // 処理を中断
    }

    // 背景画像の読み込みが完了していない場合はエラー
    if (_backgroundImage == null) {
      _showMessage('背景画像が読み込まれていません', isError: true);
      return; // 処理を中断
    }

    // === 処理開始：UIを処理中状態に変更 ===
    
    setState(() {
      _isProcessing = true; // ボタンを無効化、ローディング表示を開始
    });

    try {
      
      // === バックエンドサーバーへのリクエスト準備 ===
      
      // バックエンドサーバーのベースURL
      const serverUrl = "https://wsdcollage.onrender.com";
      
      // 画像合成APIのエンドポイントURLを構築
      final uri = Uri.parse('$serverUrl/v1/photos');

      // マルチパートリクエストを作成（ファイルアップロード用のHTTPリクエスト形式）
      final request = http.MultipartRequest('POST', uri);

      // === ユーザー選択画像をリクエストに追加 ===
      
      // MultipartFileオブジェクトを作成
      final mainImageFile = http.MultipartFile.fromBytes(
        'file',                          // バックエンドが期待するフィールド名
        _selectedImage!,                 // 画像のバイナリデータ
        filename: 'main.jpg',            // ファイル名（バックエンドでの識別用）
        contentType: MediaType('image', 'jpeg'), // MIMEタイプ（画像形式の指定）
      );
      request.files.add(mainImageFile); // リクエストにファイルを追加

      // === 背景画像をリクエストに追加 ===
      
      final backgroundImageFile = http.MultipartFile.fromBytes(
        'preset_file',                   // バックエンドが期待するフィールド名
        _backgroundImage!,               // 背景画像のバイナリデータ
        filename: 'preset.jpg',          // ファイル名
        contentType: MediaType('image', 'jpeg'), // MIMEタイプ
      );
      request.files.add(backgroundImageFile);

      // === バックエンドサーバーにリクエスト送信 ===
      
      // HTTPリクエストを送信し、レスポンスを受信
      final response = await request.send();
      
      // レスポンスのボディ（バイナリストリーム）を文字列に変換
      final responseString = await response.stream.bytesToString();
      
      // JSON文字列をMapオブジェクトに変換（Dartで扱いやすくするため）
      final responseData = jsonDecode(responseString);

      // === 成功時の処理：合成結果をUIに反映 ===
      
      setState(() {
        // バックエンドから返された画像のパスを完全なURLに変換
        _composedImageUrl = "$serverUrl/${responseData['url']}";
      });

      // ユーザーに成功メッセージを表示
      _showMessage('画像の合成が完了しました！');

    } catch (e) {
      
      // === エラー時の処理 ===
      
      // ネットワークエラー、サーバーエラー、JSONパースエラーなど
      _showMessage('エラーが発生しました: $e', isError: true);
      
    } finally {
      
      // === 処理完了：UIを通常状態に戻す ===
      
      // try-catchの結果に関わらず必ず実行される
      setState(() {
        _isProcessing = false; // ボタンを有効化、ローディング表示を終了
      });
    }
  }

  // ============================================================================
  // UI ヘルパー関数群
  // ============================================================================
  
  /// ユーザーへのメッセージ表示用のヘルパー関数
  /// 成功・エラーメッセージを画面下部にスナックバーで表示
  void _showMessage(String message, {bool isError = false}) {
    
    // Widgetがまだ画面に表示されているかチェック（メモリリーク防止）
    if (!mounted) return;

    // SnackBar（画面下部に表示される一時的なメッセージ）を表示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),                           // 表示するメッセージ
        backgroundColor: isError ? Colors.red : Colors.green, // エラー時は赤、成功時は緑
        behavior: SnackBarBehavior.floating,              // フローティング表示
      ),
    );
  }

  /// 画像表示用のカードコンテナを構築するヘルパー関数
  /// タイトル付きのカード形式で画像を表示するためのUI部品
  Widget _buildImageContainer({
    required String title,      // カードのタイトル
    required Widget child,      // カード内に表示するWidget（画像など）
    required Color titleColor,  // タイトル部分の背景色
  }) {
    return Card(
      elevation: 4, // カードの影の深さ（立体感の演出）
      child: Padding(
        padding: const EdgeInsets.all(16), // カード内の余白
        child: Column(
          children: [
            
            // === タイトル部分 ===
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: titleColor,                        // 背景色
                borderRadius: BorderRadius.circular(16),  // 角丸
              ),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,      // 白色テキスト
                  fontWeight: FontWeight.bold, // 太字
                ),
              ),
            ),
            
            const SizedBox(height: 16), // タイトルと画像の間のスペース
            
            // === 画像表示エリア ===
            Expanded(child: child), // 残りのスペースを全て使用
          ],
        ),
      ),
    );
  }

  /// 画像表示ウィジェット（バイナリデータまたはURL対応）
  /// ローカル画像とネットワーク画像の両方に対応した汎用的な画像表示機能
  Widget _buildImage({Uint8List? imageBytes, String? imageUrl}) {
    
    // === ローカル画像（バイナリデータ）の表示 ===
    if (imageBytes != null) {
      
      return ClipRRect(
        borderRadius: BorderRadius.circular(8), // 画像の角を丸く
        child: Image.memory(
          imageBytes,                    // バイナリデータから画像を表示
          fit: BoxFit.contain,          // アスペクト比を保持してコンテナにフィット
          width: double.infinity,       // 横幅を最大に
        ),
      );
      
    } 
    // === ネットワーク画像（URL）の表示 ===
    else if (imageUrl != null) {
      
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imageUrl,                      // URLから画像を読み込み
          fit: BoxFit.contain,
          width: double.infinity,
          
          // 画像読み込み中の表示（プログレスインジケーター）
          loadingBuilder: (context, child, loadingProgress) {
            // 読み込み完了時は画像を表示
            if (loadingProgress == null) return child;
            
            // 読み込み中はローディングアニメーションを表示
            return const Center(child: CircularProgressIndicator());
          },
          
          // 画像読み込みエラー時の表示
          errorBuilder: (context, error, stackTrace) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,        // 薄い赤色の背景
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, color: Colors.red, size: 48), // エラーアイコン
                  SizedBox(height: 8),
                  Text('画像の読み込みに失敗しました'),
                ],
              ),
            );
          },
        ),
      );
      
    } 
    // === 画像が無い場合のプレースホルダー ===
    else {
      
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,               // 薄い灰色の背景
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300), // 灰色の枠線
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image, size: 64, color: Colors.grey), // 画像アイコン
              SizedBox(height: 8),
              Text(
                '画像がありません',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
  }

  // ============================================================================
  // メインUI構築
  // ============================================================================
  
  /// このWidgetのUI構造を定義するメインメソッド
  /// 画面全体のレイアウトとコンポーネントの配置を管理
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      
      // === アプリバー（画面上部のヘッダー） ===
      appBar: AppBar(
        title: const Text('画像合成アプリ'),                        // アプリバーのタイトル
        backgroundColor: Theme.of(context).colorScheme.inversePrimary, // テーマカラーを使用
        centerTitle: true,                                         // タイトルを中央配置
      ),
      
      // === メインコンテンツエリア ===
      body: Padding(
        padding: const EdgeInsets.all(16.0), // 画面全体の余白
        child: Column(
          children: [
            
            // === 画像表示エリア（選択画像と合成結果を横並び表示） ===
            Expanded(
              flex: 3, // 画面の3/4を画像表示に使用
              child: Row(
                children: [
                  
                  // 左側：ユーザーが選択した画像
                  Expanded(
                    child: _buildImageContainer(
                      title: '選択した画像',              // カードタイトル
                      titleColor: Colors.blue,          // 青色のタイトル背景
                      child: _buildImage(imageBytes: _selectedImage), // 選択画像を表示
                    ),
                  ),
                  
                  const SizedBox(width: 16), // 左右のカードの間のスペース
                  
                  // 右側：バックエンドで合成された結果画像
                  Expanded(
                    child: _buildImageContainer(
                      title: '合成後の画像',              // カードタイトル
                      titleColor: Colors.green,         // 緑色のタイトル背景
                      child: _buildImage(imageUrl: _composedImageUrl), // 合成画像を表示
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20), // 画像エリアと情報エリアの間のスペース

            // === 背景画像情報表示エリア ===
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,                    // 薄いオレンジ色の背景
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200), // オレンジ色の枠線
              ),
              child: Row(
                children: [
                  
                  const Icon(Icons.info, color: Colors.orange), // 情報アイコン
                  const SizedBox(width: 8),
                  
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, // 左寄せ
                      children: [
                        
                        // 背景画像のタイトル
                        const Text(
                          '背景画像',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        
                        // 背景画像のファイルパス
                        Text(
                          _backgroundImagePath,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis, // 長いパスは省略表示
                        ),
                        
                        // 背景画像の読み込み状態表示
                        if (_backgroundImage != null)
                          // 読み込み完了時
                          Text(
                            '読み込み完了',
                            style: TextStyle(
                              color: Colors.green.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        else
                          // 読み込み中
                          Text(
                            '読み込み中...',
                            style: TextStyle(
                              color: Colors.orange.shade600,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30), // 情報エリアとボタンエリアの間のスペース

            // === アクションボタン群 ===
            Column(
              children: [
                
                // === 画像選択ボタン ===
                SizedBox(
                  width: double.infinity, // 横幅を画面いっぱいに
                  height: 50,             // ボタンの高さ
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _pickImage, // 処理中は無効化
                    icon: const Icon(Icons.photo_library),        // ギャラリーアイコン
                    label: const Text('画像を選択'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,   // 青色の背景
                      foregroundColor: Colors.white,  // 白色のテキスト・アイコン
                    ),
                  ),
                ),

                const SizedBox(height: 12), // ボタン間のスペース

                // === 合成実行ボタン ===
                SizedBox(
                  width: double.infinity, // 横幅を画面いっぱいに
                  height: 60,             // 大きめのボタン
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _composeImages, // 処理中は無効化
                    
                    // アイコンの条件分岐表示
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,      // 細めのローディングリング
                              color: Colors.white, // 白色のローディングリング
                            ),
                          )
                        : const Icon(Icons.auto_fix_high), // 魔法の杖アイコン
                    
                    // ボタンテキストの条件分岐表示
                    label: Text(_isProcessing ? '合成処理中...' : '画像を合成する'),
                    
                    style: ElevatedButton.styleFrom(
                      // 処理中は灰色、通常時は緑色
                      backgroundColor: _isProcessing ? Colors.grey : Colors.green,
                      foregroundColor: Colors.white,  // 白色のテキスト・アイコン
                      textStyle: const TextStyle(
                        fontSize: 16,                // 大きめのフォントサイズ
                        fontWeight: FontWeight.bold, // 太字
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}