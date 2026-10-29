@if($paginator->hasPages())
<nav aria-label="Páginas de lotes">
    <ul class="pagination mb-0 flex-wrap">
        <li class="page-item {{ $paginator->onFirstPage() ? 'disabled' : '' }}">
            @if($paginator->onFirstPage())<span class="page-link" aria-disabled="true">Anterior</span>
            @else<a class="page-link" href="{{ $paginator->previousPageUrl() }}" rel="prev">Anterior</a>@endif
        </li>
        @foreach($elements as $element)
            @if(is_string($element))<li class="page-item disabled"><span class="page-link">{{ $element }}</span></li>@endif
            @if(is_array($element))
                @foreach($element as $page => $url)
                    @if($page == $paginator->currentPage())<li class="page-item active" aria-current="page"><span class="page-link">{{ $page }}</span></li>
                    @else<li class="page-item"><a class="page-link" href="{{ $url }}" aria-label="Página {{ $page }}">{{ $page }}</a></li>@endif
                @endforeach
            @endif
        @endforeach
        <li class="page-item {{ !$paginator->hasMorePages() ? 'disabled' : '' }}">
            @if($paginator->hasMorePages())<a class="page-link" href="{{ $paginator->nextPageUrl() }}" rel="next">Siguiente</a>
            @else<span class="page-link" aria-disabled="true">Siguiente</span>@endif
        </li>
    </ul>
</nav>
@endif
