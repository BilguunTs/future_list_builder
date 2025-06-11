library future_list_builder;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'future_list_builder.dart';

export 'package:future_list_builder/future_list_builder.dart';
export 'src/list_state.dart';

class FutureListBuilder<T> extends StatefulWidget {
  // Core functionality
  final Future<List<T>> Function()? fixedFutureList;
  final Future<List<T>> Function(int page, int size)? dynamicFutureList;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final bool useFixedFetcher;
  final int paginationSize;

  // List processing
  final bool Function(T item)? listFilter;
  final int Function(T a, T b)? listSort;

  // UI customization
  final String titleOnEmpty;
  final Widget? emptyView;
  final Widget? customLoadingIndicator;
  final Widget? floatingTopSection;
  final Widget? fixedFirstItem;
  final bool hideDivider;
  final Divider divider;

  // Scroll configuration
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final bool reverse;
  final Axis scrollDirection;
  final EdgeInsetsGeometry? padding;
  final DragStartBehavior dragStartBehavior;
  final Clip clipBehavior;

  // Grid configuration
  final bool useGrid;
  final SliverGridDelegate gridDelegate;

  // Loading behavior
  final bool showLoadingIndicator;
  final bool freezeWhenFetch;
  final Alignment loadingIndicatorAlignment;

  // Callbacks
  final Function(List<T> items)? onFetchDone;
  final Future<void> Function()? onRefresh;
  final Function(String error)? onError;

  // State management
  final bool? shouldRefresh;

  // ListView specific
  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;
  final bool addSemanticIndexes;
  final int? Function(Key key)? findChildIndexCallback;

  const FutureListBuilder({
    Key? key,
    required this.itemBuilder,
    this.fixedFutureList,
    this.dynamicFutureList,
    this.useFixedFetcher = false,
    this.paginationSize = 10,
    this.listFilter,
    this.listSort,
    this.titleOnEmpty = 'No data available',
    this.emptyView,
    this.customLoadingIndicator,
    this.floatingTopSection,
    this.fixedFirstItem,
    this.hideDivider = true,
    this.divider = const Divider(),
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.shrinkWrap = false,
    this.reverse = false,
    this.scrollDirection = Axis.vertical,
    this.padding,
    this.dragStartBehavior = DragStartBehavior.start,
    this.clipBehavior = Clip.hardEdge,
    this.useGrid = false,
    this.gridDelegate = const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 200,
      childAspectRatio: 3 / 2,
      crossAxisSpacing: 20,
      mainAxisSpacing: 20,
    ),
    this.showLoadingIndicator = true,
    this.freezeWhenFetch = true,
    this.loadingIndicatorAlignment = Alignment.center,
    this.onFetchDone,
    this.onRefresh,
    this.onError,
    this.shouldRefresh,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.findChildIndexCallback,
  }) : assert(
         (useFixedFetcher && fixedFutureList != null) ||
             (!useFixedFetcher && dynamicFutureList != null),
         'Either fixedFutureList or dynamicFutureList must be provided based on useFixedFetcher',
       ),
       super(key: key);

  @override
  State<FutureListBuilder<T>> createState() => _FutureListBuilderState<T>();
}

class _FutureListBuilderState<T> extends State<FutureListBuilder<T>>
    with SingleTickerProviderStateMixin {
  // State variables
  List<T> _currentList = [];
  ListState _listState = ListState.loading;
  String? _errorMessage;
  bool _shouldFetchMore = true;
  bool _isFetchingMore = false;
  int _currentPage = 1;

  // Controllers
  late final ScrollController _scrollController;
  late final AnimationController _topSectionAnimationController;
  late final Animation<double> _topSectionAnimation;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _setupScrollListener();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchInitialData());
  }

  void _initializeControllers() {
    _scrollController = ScrollController();
    _topSectionAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _topSectionAnimation = Tween<double>(
      begin: -100.0,
      end: 0.0,
    ).animate(_topSectionAnimationController);
    _topSectionAnimationController.forward();
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (!widget.useFixedFetcher &&
          _scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent -
                  200 && // Preload buffer
          _shouldFetchMore &&
          !_isFetchingMore) {
        _fetchMoreData();
      }
    });
  }

  @override
  void didUpdateWidget(covariant FutureListBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shouldRefresh != widget.shouldRefresh &&
        widget.shouldRefresh == true) {
      _fetchInitialData();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _topSectionAnimationController.dispose();
    super.dispose();
  }

  // Data fetching methods
  Future<void> _fetchInitialData() async {
    if (widget.useFixedFetcher) {
      await _fetchFixedData();
    } else {
      await _fetchDynamicData(refresh: true);
    }
  }

  Future<void> _fetchFixedData() async {
    try {
      setState(() => _listState = ListState.loading);

      final List<T> rawList = await widget.fixedFutureList!();
      final List<T> processedList = _processListData(rawList);

      setState(() {
        _currentList = processedList;
        _listState = processedList.isEmpty ? ListState.empty : ListState.loaded;
        _errorMessage = null;
      });

      widget.onFetchDone?.call(_currentList);
    } catch (error) {
      _handleError(error.toString());
    }
  }

  Future<void> _fetchDynamicData({bool refresh = false}) async {
    try {
      if (refresh) {
        setState(() {
          _listState = ListState.loading;
          _currentList.clear();
          _currentPage = 1;
          _shouldFetchMore = true;
        });
      } else {
        setState(() => _isFetchingMore = true);
      }

      final List<T> rawList = await widget.dynamicFutureList!(
        _currentPage,
        widget.paginationSize,
      );
      final List<T> processedList = _processListData(rawList);

      setState(() {
        if (refresh) {
          _currentList = processedList;
          _listState =
              processedList.isEmpty ? ListState.empty : ListState.loaded;
        } else {
          _currentList.addAll(processedList);
          _currentPage++;
        }

        _shouldFetchMore = processedList.length >= widget.paginationSize;
        _isFetchingMore = false;
        _errorMessage = null;
      });

      widget.onFetchDone?.call(_currentList);
    } catch (error) {
      setState(() => _isFetchingMore = false);
      if (refresh) {
        _handleError(error.toString());
      }
    }
  }

  Future<void> _fetchMoreData() async {
    if (!_shouldFetchMore || _isFetchingMore) return;
    await _fetchDynamicData(refresh: false);
  }

  List<T> _processListData(List<T> list) {
    List<T> processed = List<T>.from(list);

    if (widget.listFilter != null) {
      processed = processed.where(widget.listFilter!).toList();
    }

    if (widget.listSort != null) {
      processed.sort(widget.listSort!);
    }

    return processed;
  }

  void _handleError(String error) {
    setState(() {
      _listState = ListState.error;
      _errorMessage = error;
    });
    widget.onError?.call(error);
  }

  // UI building methods
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      onRefresh: _onRefresh,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    switch (_listState) {
      case ListState.loading:
        return _buildLoadingState();
      case ListState.empty:
        return _buildEmptyState();
      case ListState.error:
        return _buildErrorState();
      case ListState.loaded:
        return _buildLoadedState();
    }
  }

  Widget _buildLoadingState() {
    return Stack(
      children: [
        if (widget.floatingTopSection != null)
          Positioned(child: widget.floatingTopSection!),
        Center(child: _buildLoadingIndicator()),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Stack(
      children: [
        if (widget.floatingTopSection != null)
          Positioned(child: widget.floatingTopSection!),
        Padding(
          padding: const EdgeInsets.all(16),
          child:
              widget.emptyView ??
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 64,
                      color: Theme.of(context).disabledColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.titleOnEmpty,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).disabledColor,
                      ),
                    ),
                  ],
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Stack(
      children: [
        if (widget.floatingTopSection != null)
          Positioned(child: widget.floatingTopSection!),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).disabledColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _fetchInitialData,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadedState() {
    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            // Handle scroll direction for floating sections
            return true;
          },
          child: _buildListView(),
        ),
        if (widget.floatingTopSection != null)
          Positioned(
            child: Transform.translate(
              offset: Offset(0, _topSectionAnimation.value),
              child: widget.floatingTopSection!,
            ),
          ),
        if (widget.freezeWhenFetch && _isFetchingMore)
          Positioned.fill(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.2),
            ),
          ),
        if (widget.showLoadingIndicator && _isFetchingMore)
          Align(
            alignment: widget.loadingIndicatorAlignment,
            child: _buildLoadingIndicator(),
          ),
      ],
    );
  }

  Widget _buildListView() {
    if (widget.useGrid) {
      return GridView.builder(
        gridDelegate: widget.gridDelegate,
        controller: _scrollController,
        physics: widget.physics,
        scrollDirection: widget.scrollDirection,
        reverse: widget.reverse,
        shrinkWrap: widget.shrinkWrap,
        padding: widget.padding,
        findChildIndexCallback: widget.findChildIndexCallback,
        addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
        addRepaintBoundaries: widget.addRepaintBoundaries,
        addSemanticIndexes: widget.addSemanticIndexes,
        dragStartBehavior: widget.dragStartBehavior,
        clipBehavior: widget.clipBehavior,
        itemCount: _getItemCount(),
        itemBuilder: _buildItem,
      );
    }

    return ListView.separated(
      controller: _scrollController,
      physics: widget.physics,
      scrollDirection: widget.scrollDirection,
      reverse: widget.reverse,
      shrinkWrap: widget.shrinkWrap,
      padding: widget.padding,
      findChildIndexCallback: widget.findChildIndexCallback,
      addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
      addRepaintBoundaries: widget.addRepaintBoundaries,
      addSemanticIndexes: widget.addSemanticIndexes,
      dragStartBehavior: widget.dragStartBehavior,
      clipBehavior: widget.clipBehavior,
      separatorBuilder:
          (context, index) =>
              widget.hideDivider ? const SizedBox.shrink() : widget.divider,
      itemCount: _getItemCount(),
      itemBuilder: _buildItem,
    );
  }

  int _getItemCount() {
    int count = _currentList.length;
    if (widget.fixedFirstItem != null) count++;
    if (!widget.useFixedFetcher && _shouldFetchMore && _currentList.isNotEmpty)
      count++;
    return count;
  }

  Widget _buildItem(BuildContext context, int index) {
    // Handle fixed first item
    if (widget.fixedFirstItem != null) {
      if (index == 0) return widget.fixedFirstItem!;
      index--;
    }

    // Handle loading indicator for pagination
    if (!widget.useFixedFetcher &&
        index >= _currentList.length &&
        _shouldFetchMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(child: _buildLoadingIndicator()),
      );
    }

    // Handle regular items
    if (index < _currentList.length) {
      return widget.itemBuilder(context, _currentList[index], index);
    }

    return const SizedBox.shrink();
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: EdgeInsets.all(widget.customLoadingIndicator == null ? 16 : 0),
      child:
          widget.customLoadingIndicator ??
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(),
          ),
    );
  }

  Future<void> _onRefresh() async {
    await _fetchInitialData();
    await widget.onRefresh?.call();
  }
}
